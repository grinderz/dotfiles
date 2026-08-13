from pyinfra.context import host

from util import sudoers_template

# Lenovo conservation mode toggle from the user session (waybar on-click):
# allow passwordless tee to the ideapad sysfs node
sudoers_template(
    name='render /etc/sudoers.d/battery-conservation',
    src='templates/sudoers-battery.j2',
    dest='/etc/sudoers.d/battery-conservation',
    users=host.data.conservation_users,
    node=host.data.conservation_node,
)
