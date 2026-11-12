"""Pytest isolation: point the app at throwaway DB / scratch dirs.

This file is loaded by pytest before any test module (and therefore before
``amber_podcast`` is first imported), so setting the environment variables here
guarantees ``amber_podcast.config.DB_PATH`` and ``SCRATCH_DIR`` resolve to a
per-run temporary location instead of the real production
``data/amber.db`` + shared scratch. This stops the test suite from polluting
the production database.
"""
import os
import tempfile

_TMP = tempfile.mkdtemp(prefix="amber_test_")
os.environ["AMBER_DB_PATH"] = os.path.join(_TMP, "amber_test.db")
os.environ["AMBER_SCRATCH_DIR"] = os.path.join(_TMP, "scratch")
os.environ["AMBER_GDRIVE_DIR"] = os.path.join(_TMP, "gdrive")
