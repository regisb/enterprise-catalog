import logging

from django.core.management.base import BaseCommand

from enterprise_catalog.apps.api.tasks import (
    index_enterprise_catalog_courses_in_algolia_task,
)
from enterprise_catalog.apps.catalog.algolia_utils import (
    ALGOLIA_FIELDS,
    get_indexable_course_keys,
    get_initialized_algolia_client,
)
from enterprise_catalog.apps.catalog.constants import (
    TASK_BATCH_SIZE,
    TASK_TIMEOUT,
)
from enterprise_catalog.apps.catalog.models import (
    content_metadata_with_type_course,
)
from enterprise_catalog.apps.catalog.utils import batch


logger = logging.getLogger(__name__)


class Command(BaseCommand):
    help = (
        'Reindex course data in Algolia, adding on enterprise-specific metadata'
    )

    def handle(self, *args, **options):
        """
        Initializes and configures the settings for an Algolia index, and then spins off
        a task for each batch of content_keys to reindex course data in Algolia.
        """
        # Initialize and configure the Algolia index
        get_initialized_algolia_client()

        # Retrieve indexable content_keys for all ContentMetadata records with a content type of "course"
        all_course_content_metadata = content_metadata_with_type_course()
        indexable_course_keys = get_indexable_course_keys(all_course_content_metadata)

        for content_keys_batch in batch(indexable_course_keys, batch_size=TASK_BATCH_SIZE):
            async_task = index_enterprise_catalog_courses_in_algolia_task.delay(
                content_keys=content_keys_batch,
                algolia_fields=ALGOLIA_FIELDS,
            )
            message = (
                'Spinning off task index_enterprise_catalog_courses_in_algolia_task (%s) from'
                ' the reindex_algolia command to reindex %d courses in Algolia.'
            )
            logger.info(message, async_task.task_id, len(content_keys_batch))

            # See https://docs.celeryproject.org/en/stable/reference/celery.result.html#celery.result.AsyncResult.get
            # for documentation
            async_task.get(timeout=TASK_TIMEOUT, propagate=True)
            if async_task.successful():
                message = (
                    'index_enterprise_catalog_courses_in_algolia_task (%s) from command reindex_algolia finished'
                    ' successfully.'
                )
                logger.info(message, async_task.task_id)
