# Ansible

Playbooks para preparar los nodos e instalar RKE2 (R16, R17, R18).

- `files/authorized_keys`: claves SSH **públicas** de los 5 integrantes, una por línea.
  Son las mismas que se cargan en la plantilla cloud-init (M03). Las claves privadas nunca van al repo.
