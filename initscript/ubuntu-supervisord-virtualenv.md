# Ubuntu init script for Supervisord inside Virtualenv

First of all, create your virtualenv, install supervisord inside it, create file
with name `exec` inside your virtualenv folder and paste this following script:

```
#!/bin/bash
source {{ absolute_env_path }}/bin/activate
$@
```

then add execute permission to it.

after that, download `ubuntu-supervisord-virtualenv.sh` and place it in 
`/etc/init.d/supervisord_venv`, don't forget to add `eXecute` permission.

if you want to autostart it on each boot, fire this command with *super-cow* 
permission:

```
update-rc.d supervisord_venv defaults
```

finish, now you can execute `service supervisord_venv start/stop/status`.
