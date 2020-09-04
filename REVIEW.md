A basic overview of the what should be reviewed.

### Prerequisites
- Qemu is installed

### Notes
- Django is extremely picky about file locations..., fixtures need to be in the specified directory labeled by `FIXTURE_DIR` from `settings.py`

### Sample Test Workflow
```bash
#! /usr/bin/env bash

nix build -L github:ngi-nix/mangaki#nixosConfigurations.mangaki.config.system.build.vm
result/bin/run-qemu_virtual-vm

# Login with username/password user/user
# Open Terminal with Meta (configured on login) + Enter
# Wait for `journalctl -f -u mangaki` to show an output like "Watching for file changes with StatReloader" (after migrations have been applied)

# Load test data
## Yes, I know these commands look terrible, but that's how it works based off what I've found it...
sudo -u mangaki $MANGAKI_ENV/bin/python $MANGAKI_ENV/lib/python*/site-packages/mangaki/manage.py loaddata $MANGAKI_SOURCE/fixtures/{partners,seed_data}.json
sudo -u mangaki $MANGAKI_ENV/bin/python $MANGAKI_ENV/lib/python*/site-packages/mangaki/manage.py ranking
sudo -u mangaki $MANGAKI_ENV/bin/python $MANGAKI_ENV/lib/python*/site-packages/mangaki/manage.py top --all

# Load `localhost:8000` in Chromium
chromium &
disown # exit terminal
# Verify sign up, logout, and login with whatever credentials
# Verify pages `Anime > {Mosaic, Popular, Controversial}`, `Artists`, `Top 20 > {Directors, Composers, Authors}` have content
# Verify other pages can load (albiet with no content)
# Like any random anime and verify `Recommendations` becomes populated with bogus content

# Remove image once done testing
rm qemu_virtual.qcow2
```
