import logging
from typing import List, Dict, Any
import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

logger = logging.getLogger(__name__)


class DUAPIClient:
    """Client for Ducks Unlimited ArcGIS Feature Server API."""

    def __init__(self, base_url: str, timeout: int = 30, max_retries: int = 3,
                 retry_backoff: int = 2):
        """Initialize API client."""
        self.base_url = base_url
        self.timeout = timeout
        self.max_retries = max_retries
        self.retry_backoff = retry_backoff
        self.session = self._create_session()

    def _create_session(self) -> requests.Session:
        """Create a requests session with retry strategy."""
        session = requests.Session()
        retry_strategy = Retry(
            total=self.max_retries,
            status_forcelist=[429, 500, 502, 503, 504],
            allowed_methods=["GET"],
            backoff_factor=self.retry_backoff
        )
        adapter = HTTPAdapter(max_retries=retry_strategy)
        session.mount("http://", adapter)
        session.mount("https://", adapter)
        return session

    def fetch_chapters(self) -> List[Dict[str, Any]]:
        """Fetch all university chapters from ArcGIS Feature Server."""
        logger.info(f"Fetching chapters from DU API")

        response = self.session.get(self.base_url, timeout=self.timeout)
        response.raise_for_status()
        data = response.json()

        # Parse ArcGIS FeatureServer response
        features = data.get("features", [])
        logger.info(f"Successfully fetched {len(features)} records from API")

        # Convert from ArcGIS format to our format
        chapters = []
        for feature in features:
            attrs = feature.get("attributes", {})
            geom = feature.get("geometry", {})

            chapter = {
                "id": str(attrs.get("ChapterID", "")),
                "name": attrs.get("University_Chapter", ""),
                "city": attrs.get("City", ""),
                "state": attrs.get("State", ""),
                "latitude": geom.get("y", 0),
                "longitude": geom.get("x", 0)
            }
            chapters.append(chapter)

        return chapters

    def close(self):
        """Close the session."""
        self.session.close()


def extract_chapters(client: DUAPIClient, state_filter: str = "CA") -> List[Dict[str, Any]]:
    """Extract and filter chapters from API."""
    all_chapters = client.fetch_chapters()
    filtered = [
        ch for ch in all_chapters
        if ch.get("state", "").upper() == state_filter.upper()
    ]
    logger.info(f"Filtered {len(filtered)} chapters for state {state_filter}")
    return filtered


def validate_chapter(chapter: Dict[str, Any]) -> bool:
    """Validate a chapter record has required fields."""
    required_fields = {"id", "name", "city", "state", "latitude", "longitude"}

    if not all(field in chapter for field in required_fields):
        missing = required_fields - set(chapter.keys())
        logger.warning(f"Chapter missing fields: {missing}. Data: {chapter}")
        return False

    try:
        lat = float(chapter.get("latitude", 0))
        lon = float(chapter.get("longitude", 0))
        if not (-90 <= lat <= 90):
            logger.warning(f"Invalid latitude {lat} for chapter {chapter.get('id')}")
            return False
        if not (-180 <= lon <= 180):
            logger.warning(f"Invalid longitude {lon} for chapter {chapter.get('id')}")
            return False
    except (ValueError, TypeError) as e:
        logger.warning(f"Could not parse coordinates for chapter {chapter.get('id')}: {e}")
        return False

    return True