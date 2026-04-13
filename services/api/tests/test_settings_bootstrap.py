import os

from app.settings import Settings

ENV_FILE_AT_MODULE_IMPORT = Settings.model_config["env_file"]
LLM_PROVIDER_ENV_AT_MODULE_IMPORT = os.environ.get("MTG_SCANNER_LLM_PROVIDER")

from app.main import settings as app_settings


def test_dotenv_is_disabled_before_app_import() -> None:
    assert ENV_FILE_AT_MODULE_IMPORT == ()
    assert LLM_PROVIDER_ENV_AT_MODULE_IMPORT is None
    assert Settings.model_config["env_file"] == ()
    assert app_settings.__class__ is Settings
    assert app_settings.mtg_scanner_llm_provider is None
