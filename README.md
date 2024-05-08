## Logging and Output

```python
def user_msg(msg: str) -> None:
  """log to user's stdout"""
  pass

def info(msg: str) -> None:
  """log to slurmctld as info"""
  pass

def error(msg: str) -> None:
  """log to slurmctld as error"""
  pass
```

### Usage

```python
import slurm

def job_submit(job_desc, submit_uid):
  slurm.user_msg(json.dumps(job_desc))
```

