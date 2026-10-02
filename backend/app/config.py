"""Runtime configuration, read from environment variables (or backend/.env).

Every default here is for local development only. Production values are set in
deploy/.env on the VM (see deploy/.env.example).
"""
from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # ── core ──
    database_url: str = "postgresql://tarajuu:tarajuu@localhost:5432/tarajuu"
    jwt_secret: str = "dev-only-change-me"
    jwt_ttl_days: int = 30
    cors_origins: str = "*"

    # ── auth (Firebase: phone OTP + Google) ──
    firebase_project_id: str = ""

    # ── product data ──
    amazon_enabled: bool = True
    amazon_host: str = "https://www.amazon.in"
    amazon_partner_tag: str = ""  # optional Associates tag appended to buy links
    flipkart_affiliate_id: str = ""
    flipkart_affiliate_token: str = ""
    # "direct": the API server fetches amazon.in itself.
    # "agent": jobs are queued and a scrape agent (python -m app.agent) running on
    # an ordinary internet connection claims them — for cloud IPs Amazon rejects.
    scrape_mode: str = "direct"
    agent_token: str = ""
    agent_api: str = ""  # used by the agent process: the API base URL it polls
    search_cache_minutes: int = 60
    detail_cache_hours: int = 6
    scrape_timeout_seconds: float = 15.0

    # ── rides ──
    uber_client_id: str = ""
    uber_client_secret: str = ""
    uber_scope: str = "guests.trips"
    uber_api_base: str = "https://api.uber.com"
    # Guest Rides: trips are billed to this Uber for Business organization.
    uber_org_uuid: str = ""
    # Book trips through the API (else the app hands off to the Uber app via deep link).
    uber_booking_enabled: bool = False
    # Sandbox: no real drivers. Set UBER_SANDBOX=true and a run id from POST /v1/guests/sandbox/run.
    uber_sandbox: bool = False
    uber_sandbox_run_id: str = ""
    osrm_base: str = "https://router.project-osrm.org"
    photon_base: str = "https://photon.komoot.io"
    contact_email: str = "support@tarajuu.app"  # sent in User-Agent to OSM services

    @property
    def flipkart_enabled(self) -> bool:
        return bool(self.flipkart_affiliate_id and self.flipkart_affiliate_token)

    @property
    def uber_enabled(self) -> bool:
        return bool(self.uber_client_id and self.uber_client_secret)


@lru_cache
def get_settings() -> Settings:
    return Settings()
