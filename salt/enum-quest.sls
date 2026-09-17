{# ENUM QUEST — apply on all three roles via grain `role`
 #   jumpbox | ubuntu-target | win-target
 # Copy scripts to the minion (or salt://enum_lab/) before apply.
 #}
{% set role = salt['grains.get']('role', '') %}
{% set files_root = salt['pillar.get']('enum_quest:files_root', '/srv/enum_lab') %}

{% if role == 'jumpbox' %}
enum-quest-jumpbox:
  cmd.run:
    - name: >
        TARGET_UBUNTU_IP='{{ salt['pillar.get']('enum_quest:ubuntu_ip', '192.168.1.11') }}'
        TARGET_WIN_IP='{{ salt['pillar.get']('enum_quest:win_ip', '192.168.1.12') }}'
        TARGET_UBUNTU_HOST='{{ salt['pillar.get']('enum_quest:ubuntu_host', 'vault-web') }}'
        TARGET_WIN_HOST='{{ salt['pillar.get']('enum_quest:win_host', 'vault-dc') }}'
        LAB_DOMAIN='{{ salt['pillar.get']('enum_quest:lab_domain', 'vault.lab') }}'
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
        TARGET_UBUNTU_IP='{{ salt['pillar.get']('enum_quest:ubuntu_ip', '192.168.1.11') }}'
        TARGET_WIN_IP='{{ salt['pillar.get']('enum_quest:win_ip', '192.168.1.12') }}'
        TARGET_UBUNTU_HOST='{{ salt['pillar.get']('enum_quest:ubuntu_host', 'vault-web') }}'
        TARGET_WIN_HOST='{{ salt['pillar.get']('enum_quest:win_host', 'vault-dc') }}'
        LAB_DOMAIN='{{ salt['pillar.get']('enum_quest:lab_domain', 'vault.lab') }}'
        JUMPBOX_CIDR='{{ salt['pillar.get']('enum_quest:jumpbox_cidr', '192.168.1.0/24') }}'
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
        -UbuntuIp '{{ salt['pillar.get']('enum_quest:ubuntu_ip', '192.168.1.11') }}'
        -WinIp '{{ salt['pillar.get']('enum_quest:win_ip', '192.168.1.12') }}'
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
