"""Configuration management for DU ETL pipeline."""
import os
import logging
from typing import Optional
from dataclasses import dataclass

from dotenv import load_dotenv

load_dotenv()

@dataclass
class DatabaseConfig:
    """PostgreSQL database configuration."""
    host: str
    port: int
    user: str
    password: str
    database: str
    
    def get_connection_string(self) -> str:
        """Return psycopg2 connection string."""
        return (
            f"postgresql://{self.user}:{self.password}@{self.host}:{self.port}/{self.database}"
        )


@dataclass
class APIConfig:
    """Ducks Unlimited API configuration."""
    base_url: str
    timeout_seconds: int
    max_retries: int
    retry_backoff_seconds: int


@dataclass
class ETLConfig:
    """Overall ETL configuration."""
    database: DatabaseConfig
    api: APIConfig
    state_filter: str  # E.g., "CA"
    log_level: str


def load_config() -> ETLConfig:
    """
    Load configuration from environment variables.
    
    Expects:
    - DB_HOST, DB_PORT, DB_USER, DB_PASSWORD, DB_NAME
    - DU_API_BASE_URL
    - STATE_FILTER (default: "CA")
    - LOG_LEVEL (default: "INFO")
    
    Returns:
        ETLConfig: Configuration object
        
    Raises:
        ValueError: If required env vars are missing
    """
    # Database config
    db_host = os.getenv("DB_HOST")
    db_port = os.getenv("DB_PORT", "5432")
    db_user = os.getenv("DB_USER")
    db_password = os.getenv("DB_PASSWORD")
    db_name = os.getenv("DB_NAME", "du_chapters")
    
    if not all([db_host, db_user, db_password]):
        raise ValueError("Missing required database environment variables: DB_HOST, DB_USER, DB_PASSWORD")
    
    db_config = DatabaseConfig(
        host=db_host,
        port=int(db_port),
        user=db_user,
        password=db_password,
        database=db_name
    )
    
    # API config
    api_base_url = os.getenv("DU_API_BASE_URL", "https://www.ducks.org/api/university-chapters")
    api_config = APIConfig(
        base_url=api_base_url,
        timeout_seconds=int(os.getenv("API_TIMEOUT_SECONDS", "30")),
        max_retries=int(os.getenv("API_MAX_RETRIES", "3")),
        retry_backoff_seconds=int(os.getenv("API_RETRY_BACKOFF_SECONDS", "2"))
    )
    
    # ETL config
    state_filter = os.getenv("STATE_FILTER", "CA")
    log_level = os.getenv("LOG_LEVEL", "INFO")
    
    return ETLConfig(
        database=db_config,
        api=api_config,
        state_filter=state_filter,
        log_level=log_level
    )


def setup_logging(log_level: str) -> logging.Logger:
    """
    Configure logging for the pipeline.
    
    Args:
        log_level: Logging level (DEBUG, INFO, WARNING, ERROR)
        
    Returns:
        Configured logger instance
    """
    logging.basicConfig(
        level=getattr(logging, log_level.upper()),
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    return logging.getLogger(__name__)
