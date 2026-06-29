import logging
from typing import List, Dict, Any
import psycopg2
from psycopg2.extras import execute_values


logger = logging.getLogger(__name__)


class PostgresLoader:
    """Handles database connections and data loading."""
    
    def __init__(self, connection_string: str):
        """
        Initialize loader.
        
        Args:
            connection_string: PostgreSQL connection string
        """
        self.connection_string = connection_string
        self.conn = None
    
    def connect(self):
        """Establish database connection."""
        try:
            self.conn = psycopg2.connect(self.connection_string)
            logger.info("Connected to PostgreSQL database")
        except psycopg2.Error as e:
            logger.error(f"Failed to connect to database: {e}")
            raise
    
    def create_table(self):
        """Create chapters table if it doesn't exist."""
        create_sql = """
        CREATE TABLE IF NOT EXISTS chapters (
            chapter_id VARCHAR(100) PRIMARY KEY,
            chapter_name VARCHAR(255) NOT NULL,
            city VARCHAR(100) NOT NULL,
            state VARCHAR(2) NOT NULL,
            latitude DECIMAL(10, 8) NOT NULL,
            longitude DECIMAL(11, 8) NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
        CREATE INDEX IF NOT EXISTS idx_state_city ON chapters (state, city);
        """
        try:
            cursor = self.conn.cursor()
            cursor.execute(create_sql)
            self.conn.commit()
            cursor.close()
            logger.info("Created chapters table (or it already exists)")
        except psycopg2.Error as e:
            logger.error(f"Failed to create table: {e}")
            self.conn.rollback()
            raise
    
    def upsert_chapters(self, chapters: List[Dict[str, Any]]) -> int:
        """
        Insert or update chapters (upsert).
        
        Args:
            chapters: List of chapter dictionaries
            
        Returns:
            Number of rows affected
        """
        if not chapters:
            logger.warning("No chapters to upsert")
            return 0
        
        # Prepare data tuples (no updated_at - it will be set by DB)
        data_tuples = [
            (
                ch["id"],
                ch["name"],
                ch["city"],
                ch["state"],
                float(ch["latitude"]),
                float(ch["longitude"])
            )
            for ch in chapters
        ]
        
        # SQL for upsert (INSERT ... ON CONFLICT DO UPDATE)
        upsert_sql = """
        INSERT INTO chapters (chapter_id, chapter_name, city, state, latitude, longitude)
        VALUES %s
        ON CONFLICT (chapter_id) DO UPDATE SET
            chapter_name = EXCLUDED.chapter_name,
            city = EXCLUDED.city,
            state = EXCLUDED.state,
            latitude = EXCLUDED.latitude,
            longitude = EXCLUDED.longitude,
            updated_at = CURRENT_TIMESTAMP;
        """
        
        try:
            cursor = self.conn.cursor()
            execute_values(cursor, upsert_sql, data_tuples)
            self.conn.commit()
            rows_affected = cursor.rowcount
            cursor.close()
            logger.info(f"Upserted {rows_affected} chapters")
            return rows_affected
        except psycopg2.Error as e:
            logger.error(f"Failed to upsert chapters: {e}")
            self.conn.rollback()
            raise
    
    def get_chapter_count(self) -> int:
        """Get total number of chapters in database."""
        try:
            cursor = self.conn.cursor()
            cursor.execute("SELECT COUNT(*) FROM chapters;")
            count = cursor.fetchone()[0]
            cursor.close()
            return count
        except psycopg2.Error as e:
            logger.error(f"Failed to get chapter count: {e}")
            raise
    
    def get_chapters_by_state(self, state: str) -> List[Dict[str, Any]]:
        """
        Get chapters for a specific state.
        
        Args:
            state: State abbreviation (e.g., "CA")
            
        Returns:
            List of chapter dictionaries
        """
        try:
            cursor = self.conn.cursor()
            cursor.execute(
                "SELECT chapter_id, chapter_name, city, state, latitude, longitude FROM chapters WHERE state = %s;",
                (state.upper(),)
            )
            rows = cursor.fetchall()
            cursor.close()
            return [
                {
                    "id": row[0],
                    "name": row[1],
                    "city": row[2],
                    "state": row[3],
                    "latitude": row[4],
                    "longitude": row[5]
                }
                for row in rows
            ]
        except psycopg2.Error as e:
            logger.error(f"Failed to get chapters by state: {e}")
            raise
    
    def close(self):
        """Close database connection."""
        if self.conn:
            self.conn.close()
            logger.info("Closed database connection")