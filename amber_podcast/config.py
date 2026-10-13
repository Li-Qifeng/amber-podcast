import os
from pathlib import Path

# Paths
BASE_DIR = Path(__file__).resolve().parent.parent
DATA_DIR = BASE_DIR / "data"
DATA_DIR.mkdir(parents=True, exist_ok=True)

DB_PATH = os.environ.get("AMBER_DB_PATH", str(DATA_DIR / "amber.db"))
GDRIVE_DIR = Path(os.environ.get("AMBER_GDRIVE_DIR", "/mnt/gdrive/podcasts"))
SCRATCH_DIR = Path(os.environ.get("AMBER_SCRATCH_DIR", "/root/.hermes/cache/scratch/amber"))
SCRATCH_DIR.mkdir(parents=True, exist_ok=True)

# Auth
AUTH_TOKEN = os.environ.get("AMBER_AUTH_TOKEN", "amber-secret-token-2026")

# External APIs
GROQ_API_KEY = os.environ.get("GROQ_API_KEY", "")
OPENROUTER_API_KEY = os.environ.get("OPENROUTER_API_KEY", "")
GOOGLE_PROJECT_ID = os.environ.get("GOOGLE_PROJECT_ID", "project-7fc6f406-0fd7-4292-903")

# LLM Gateway (Antigravity Manager / Local proxy)
GCLI_BASE_URL = os.environ.get("GCLI_BASE_URL", "http://127.0.0.1:8045/v1")
GCLI_API_KEY = os.environ.get("GCLI_API_KEY", "")

# Server
SERVER_HOST = os.environ.get("AMBER_HOST", "127.0.0.1")
SERVER_PORT = int(os.environ.get("AMBER_PORT", "8910"))
