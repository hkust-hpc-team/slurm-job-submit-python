import json
import slurm
import traceback

INFO = " [INFO]"
INF2 = " [info]"
WARN = " [WARN]"
ERROR = "[ERROR]"


def job_submit(job_desc, submit_uid):
    try:
        slurm.user_msg(json.dumps(job_desc))
        msg = f"{INFO} Job submitted by {submit_uid}."
        slurm.user_msg(msg)
        slurm.info(msg)
        slurm.error(msg)
        return 0
    except Exception as e:
        slurm.error(traceback.format_exc())
        slurm.user_msg(f"{ERROR} {e}")
        return -1
