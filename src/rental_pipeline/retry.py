from collections.abc import Callable
import logging, time

logger = logging.getLogger(__name__)

def run_with_retry[T](func: Callable[[],T], retry_on: tuple[type[Exception], ...]) -> T:
    max_retries = 3
    for i in range(max_retries):
        try:
            page = func()
            break
        except retry_on as err:
            if i != max_retries - 1:
                logger.warning("Attempt no.%s failed %s", i+1, err)
                time.sleep(pow(2,i))
            else:
                logger.error("Attempt no.%s failed %s", i+1, err)
                raise
    return page
