"""Main ETL pipeline - orchestrates extract, transform, load."""
import logging
import sys
from src.config import load_config, setup_logging
from src.extractors.du_api import DUAPIClient, extract_chapters, validate_chapter
from src.loaders.postgres import PostgresLoader


logger = logging.getLogger(__name__)


def run_etl():
    """
    Execute the complete ETL pipeline.
    
    Flow:
    1. Load configuration from environment
    2. Initialize API client and fetch chapters
    3. Validate and filter chapters
    4. Connect to database and create table
    5. Upsert chapters into database
    6. Log results and metrics
    
    Raises:
        Exception: If any step fails
    """
    try:
        # 1. Load configuration
        logger.info("Loading configuration...")
        config = load_config()
        
        # 2. Initialize API client
        logger.info("Initializing API client...")
        api_client = DUAPIClient(
            base_url=config.api.base_url,
            timeout=config.api.timeout_seconds,
            max_retries=config.api.max_retries,
            retry_backoff=config.api.retry_backoff_seconds
        )
        
        # 3. Extract and filter chapters
        logger.info(f"Extracting chapters for state: {config.state_filter}")
        all_chapters = extract_chapters(api_client, config.state_filter)
        
        if not all_chapters:
            logger.warning(f"No chapters found for state {config.state_filter}")
            return
        
        # 4. Validate chapters
        logger.info(f"Validating {len(all_chapters)} chapters...")
        valid_chapters = [ch for ch in all_chapters if validate_chapter(ch)]
        invalid_count = len(all_chapters) - len(valid_chapters)
        
        if invalid_count > 0:
            logger.warning(f"Skipped {invalid_count} invalid chapters")
        
        if not valid_chapters:
            logger.error("No valid chapters to load")
            return
        
        # 5. Connect to database and load data
        logger.info("Initializing database loader...")
        loader = PostgresLoader(config.database.get_connection_string())
        
        loader.connect()
        loader.create_table()
        
        logger.info(f"Upserting {len(valid_chapters)} chapters into database...")
        rows_affected = loader.upsert_chapters(valid_chapters)
        
        # 6. Log final metrics
        total_count = loader.get_chapter_count()
        logger.info(f"✓ ETL pipeline completed successfully")
        logger.info(f"  - Chapters upserted: {rows_affected}")
        logger.info(f"  - Total chapters in DB: {total_count}")
        
        loader.close()
        api_client.close()
        
    except Exception as e:
        logger.error(f"ETL pipeline failed: {e}", exc_info=True)
        sys.exit(1)


if __name__ == "__main__":
    # Setup logging first
    config = load_config()
    setup_logging(config.log_level)
    
    run_etl()
