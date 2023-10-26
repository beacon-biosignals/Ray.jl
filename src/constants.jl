# NOTES:
#
# python function manager maintains a local table of "execution info" with a
# "function_id" key and values that are named tuples of name/function/max_calls.
#
# python remote function sets a UUID4 at construction time:
# https://github.com/beacon-biosignals/ray/blob/7ad1f47a9c849abf00ca3e8afc7c3c6ee54cda43/python/ray/remote_function.py#L128
#
# ...that's used to set the function_hash (???)...
# https://github.com/beacon-biosignals/ray/blob/7ad1f47a9c849abf00ca3e8afc7c3c6ee54cda43/python/ray/remote_function.py#L263-L265
#
# later comment suggests that "ideally" they'd use the hash of the pickled
# function:
# https://github.com/beacon-biosignals/ray/blob/7ad1f47a9c849abf00ca3e8afc7c3c6ee54cda43/python/ray/includes/function_descriptor.pxi#L183-L186
#
# ...but that it's not stable for some reason.  but.....neither is a random
# UUID?????
#
# the function table key is built like
# <key type>:<jobid>:key

# function manager holds:
# local cache of functions (keyed by function id/hash from descriptor)
# gcs client
# ~~maybe job id?~~ this is managed by the core worker process

# https://github.com/beacon-biosignals/ray/blob/1c0cddc478fa33d4c244d3c30aba861a77b0def9/python/ray/_private/ray_constants.py#L122-L123
const FUNCTION_SIZE_WARN_THRESHOLD = 10_000_000  # in bytes
const FUNCTION_SIZE_ERROR_THRESHOLD = 100_000_000  # in bytes

# python uses "fun" for the namespace: https://github.com/beacon-biosignals/ray/blob/7ad1f47a9c849abf00ca3e8afc7c3c6ee54cda43/python/ray/_private/ray_constants.py#L380
# so "jlfun" seems reasonable
const FUNCTION_MANAGER_NAMESPACE = "jlfun"

# env var to control whether logs are sent do stderr or to file.  if "1", sent
# to stderr; otherwise, will be sent to files in `/tmp/ray/session_latest/logs/`
# https://github.com/beacon-biosignals/ray/blob/4ceb62daaad05124713ff9d94ffbdad35ee19f86/python/ray/_private/ray_constants.py#L198
const LOGGING_REDIRECT_STDERR_ENVIRONMENT_VARIABLE = "RAY_LOG_TO_STDERR"

const DEFAULT_SESSION_DIR = "/tmp/ray/session_latest"

const GCS_ADDRESS_FILE = "/tmp/ray/ray_current_cluster"
