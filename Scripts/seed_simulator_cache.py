"""Optional simulator QA helper when the simulator's DNS is unavailable.
Fetches real public data on the Mac and puts it in the app's existing cache.
Does not change app networking, use demo lessons, or affect a physical iPhone.
Stop the app first and pass the app's simulator data-container path.
"""
import datetime
import json
from pathlib import Path
import sys
import subprocess

container = Path(sys.argv[1]).resolve()
if 'CoreSimulator/Devices' not in str(container) or not container.is_dir():
    raise SystemExit('Expected an existing CoreSimulator app data container')
now = datetime.datetime.now(datetime.timezone.utc)
moscow = now.astimezone(datetime.timezone(datetime.timedelta(hours=3)))
monday = moscow.date() - datetime.timedelta(days=moscow.weekday())
cache_file = container/'Library/Application Support/Polytech/schedule.json'
cache = json.loads(cache_file.read_text()) if cache_file.exists() else {}
for offset in [0, 7]:
    date = (monday + datetime.timedelta(days=offset)).isoformat()
    url = f'https://ruz.spbstu.ru/api/v1/ruz/scheduler/45602?date={date}'
    week = json.loads(subprocess.check_output(["curl", "--fail", "--silent", "--show-error", "--location", "--max-time", "30", url]))
    assert week['group']['id'] == 45602
    cache[f'45602-{date}'] = {
        'response': week,
        'fetchedAt': (now-datetime.datetime(2001, 1, 1, tzinfo=datetime.timezone.utc)).total_seconds()
    }
cache_file.parent.mkdir(parents=True, exist_ok=True)
cache_file.write_text(json.dumps(cache, ensure_ascii=False))
print('Cached two weeks of real university data for simulator QA.')
