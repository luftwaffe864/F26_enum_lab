{# ENUM QUEST — apply on all three roles via grain `role`
 #   jumpbox | ubuntu-target | win-target
 #
 # Each team pod uses the same IPs on an isolated 192.168.1.0/24:
 #   Jumpbox 192.168.1.7 · Ubuntu 192.168.1.10 · Windows 192.168.1.11
 #}
{% set role = salt['grains.get']('role', '') %}
{% set files_root = salt['pillar.get']('enum_quest:files_root', '/srv/enum_lab') %}
{% set ubuntu_ip = salt['pillar.get']('enum_quest:ubuntu_ip', '192.168.1.10') %}
{% set win_ip = salt['pillar.get']('enum_quest:win_ip', '192.168.1.11') %}
{% set jumpbox_ip = salt['pillar.get']('enum_quest:jumpbox_ip', '192.168.1.7') %}
{% set cidr = salt['pillar.get']('enum_quest:jumpbox_cidr', '192.168.1.0/24') %}

{% if role == 'jumpbox' %}
enum-quest-jumpbox:
  cmd.run:
    - name: >
        JUMPBOX_IP='{{ jumpbox_ip }}'
        TARGET_UBUNTU_IP='{{ ubuntu_ip }}'
        TARGET_WIN_IP='{{ win_ip }}'
        TARGET_UBUNTU_HOST='{{ salt['pillar.get']('enum_quest:ubuntu_host', 'vault-web') }}'
        TARGET_WIN_HOST='{{ salt['pillar.get']('enum_quest:win_host', 'vault-dc') }}'
        LAB_DOMAIN='{{ salt['pillar.get']('enum_quest:lab_domain', 'vault.lab') }}'
        JUMPBOX_CIDR='{{ cidr }}'
        bash {{ files_root }}/setup_jumpbox.sh --no-switch
          {% if salt['pillar.get']('enum_quest:player_user') %}
          --user {{ salt['pillar.get']('enum_quest:player_user') }}
          {% endif %}
    - require:
      - file: enum-quest-files

{% elif role == 'ubuntu-target' %}
enum-quest-ubuntu-target:
  cmd.run:
    - name: >
        TARGET_UBUNTU_IP='{{ ubuntu_ip }}'
        TARGET_WIN_IP='{{ win_ip }}'
        TARGET_UBUNTU_HOST='{{ salt['pillar.get']('enum_quest:ubuntu_host', 'vault-web') }}'
        TARGET_WIN_HOST='{{ salt['pillar.get']('enum_quest:win_host', 'vault-dc') }}'
        LAB_DOMAIN='{{ salt['pillar.get']('enum_quest:lab_domain', 'vault.lab') }}'
        JUMPBOX_CIDR='{{ cidr }}'
        bash {{ files_root }}/setup_ubuntu_target.sh --no-switch
    - require:
      - file: enum-quest-files

{% elif role == 'win-target' %}
enum-quest-win-target:
  cmd.run:
    - name: >
        powershell -ExecutionPolicy Bypass -File {{ files_root }}\setup_win_target.ps1
        -LabDomain '{{ salt['pillar.get']('enum_quest:lab_domain', 'vault.lab') }}'
        -UbuntuHost '{{ salt['pillar.get']('enum_quest:ubuntu_host', 'vault-web') }}'
        -WinHost '{{ salt['pillar.get']('enum_quest:win_host', 'vault-dc') }}'
        -UbuntuIp '{{ ubuntu_ip }}'
        -WinIp '{{ win_ip }}'
    - shell: powershell
    - require:
      - file: enum-quest-files

{% else %}
enum-quest-role-missing:
  test.fail_without_changes:
    - name: "Set grain role=jumpbox|ubuntu-target|win-target before applying enum-quest"
{% endif %}

enum-quest-files:
  file.recurse:
    - name: {{ files_root }}
    - source: salt://enum_lab
    - clean: False
    - dir_mode: 755
    - file_mode: 755
