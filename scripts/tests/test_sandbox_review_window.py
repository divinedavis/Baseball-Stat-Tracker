"""Offline tests for the App Review sandbox window (no network, no PAT).

    python3 -m unittest discover -s scripts/tests
"""
import io
import json
import os
import sys
import unittest
from contextlib import redirect_stdout
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import sandbox_review_window as srw  # noqa: E402


class FakeResp(io.BytesIO):
    status = 200

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False


def fake_urlopen(rows, sink):
    def _open(req, timeout=None):
        sink.append(req)
        return FakeResp(json.dumps(rows).encode())
    return _open


class OpenSqlTests(unittest.TestCase):
    def test_default_is_14_days_and_never_shortens(self):
        sql = srw.open_sql(srw.DEFAULT_DAYS)
        self.assertEqual(srw.DEFAULT_DAYS, 14)
        self.assertIn("interval '14 days'", sql)
        self.assertIn("greatest(coalesce(sandbox_grants_open_until, now())", sql)
        self.assertIn("public.billing_settings", sql)
        self.assertIn("returning sandbox_grants_open_until", sql)

    def test_live_sql_test_runs_the_same_statement(self):
        path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..",
                            "supabase", "tests", "sql", "sandbox_review_window.test.sql")
        with open(path) as f:
            self.assertIn(srw.open_sql(14).rstrip(";") + " into t;", f.read())

    def test_rejects_bad_days(self):
        for bad in (0, -1, 31, "14", 1.5, True, None):
            with self.assertRaises(ValueError, msg=repr(bad)):
                srw.open_sql(bad)


class RunSqlTests(unittest.TestCase):
    def setUp(self):
        self.env = mock.patch.dict(os.environ, {"SUPABASE_ACCESS_TOKEN": "pat-xyz"})
        self.env.start()

    def tearDown(self):
        self.env.stop()

    def test_open_window_posts_to_query_endpoint_and_prints_until(self):
        sent = []
        rows = [{"sandbox_grants_open_until": "2026-10-21T12:00:00+00:00"}]
        out = io.StringIO()
        with mock.patch("urllib.request.urlopen", fake_urlopen(rows, sent)), redirect_stdout(out):
            until = srw.open_window()
        self.assertEqual(until, "2026-10-21T12:00:00+00:00")
        self.assertIn("2026-10-21T12:00:00+00:00", out.getvalue())
        self.assertNotIn("pat-xyz", out.getvalue())
        req = sent[0]
        self.assertTrue(req.full_url.endswith(f"/v1/projects/{srw.REF}/database/query"))
        self.assertNotIn("postgrest", req.full_url)  # never the jwt_secret endpoint
        self.assertEqual(req.get_method(), "POST")
        self.assertIn("interval '14 days'", json.loads(req.data)["query"])
        self.assertEqual(req.get_header("User-agent"), "curl/8.7.1")

    def test_missing_row_raises(self):
        with mock.patch("urllib.request.urlopen", fake_urlopen([], [])):
            with self.assertRaises(RuntimeError):
                srw.open_window()

    def test_extend_if_in_review_only_opens_while_in_review(self):
        with mock.patch.object(srw, "open_window") as ow, mock.patch.object(srw, "status") as st:
            with mock.patch.object(srw, "versions_in_review", return_value=[]), redirect_stdout(io.StringIO()):
                srw.main(["extend-if-in-review"])
            ow.assert_not_called()
            st.assert_called_once()
            with mock.patch.object(srw, "versions_in_review", return_value=["1.3"]), redirect_stdout(io.StringIO()):
                srw.main(["extend-if-in-review", "--days", "7"])
            ow.assert_called_once_with(7)


class SubmitScriptsOpenWindowFirst(unittest.TestCase):
    """Each script that PATCHes submitted=true must open the window first and
    must not submit if opening fails."""

    def _check(self, module_name, call, api_reply=lambda m, p: (200, {"data": []})):
        try:
            mod = __import__(module_name)
        except (ImportError, SystemExit) as e:  # PyJWT missing in this interpreter
            self.skipTest(str(e))
        order = []
        with mock.patch.object(mod, "open_window", side_effect=lambda *a: order.append("open")), \
             mock.patch.object(mod, "api", side_effect=lambda m, p, *a, **k: (order.append(m), api_reply(m, p))[1]), \
             redirect_stdout(io.StringIO()):
            call(mod)
        self.assertIn("open", order)
        self.assertLess(order.index("open"), len(order) - 1 - order[::-1].index("PATCH"))

        with mock.patch.object(mod, "open_window", side_effect=RuntimeError("down")), \
             mock.patch.object(mod, "api", side_effect=lambda m, p, *a, **k: api_reply(m, p)) as api, \
             redirect_stdout(io.StringIO()):
            with self.assertRaises(RuntimeError):
                call(mod)
            self.assertFalse(any(c.args[0] == "PATCH" for c in api.call_args_list))

    def test_resubmit_with_iaps(self):
        self._check("asc_resubmit_with_iaps", lambda m: m.submit_for_review("sub1", "tok", dry=False))

    def test_submit_for_review(self):
        def reply(method, path):
            if path.startswith("/v1/reviewSubmissions?"):
                return 200, {"data": [{"id": "sub1", "attributes": {"state": "READY_FOR_REVIEW"}}]}
            if path.endswith("/items"):
                return 200, {"data": [{"relationships": {"appStoreVersion": {"data": {"id": "v1"}}}}]}
            return 200, {"data": {}}
        self._check("asc_submit_for_review",
                    lambda m: m.submit_for_review("app", "v1", "tok"), reply)

    def test_resubmit_dry_run_touches_nothing(self):
        try:
            import asc_resubmit_with_iaps as m
        except ImportError as e:
            self.skipTest(str(e))
        with mock.patch.object(m, "open_window") as ow, mock.patch.object(m, "api") as api, \
             redirect_stdout(io.StringIO()):
            m.submit_for_review("sub1", "tok", dry=True)
        ow.assert_not_called()
        api.assert_not_called()


if __name__ == "__main__":
    unittest.main()
