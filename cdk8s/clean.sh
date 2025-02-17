yq -i '(select(.data[]) | .data[]) style="double"' ./dist/0002-dev.k8s.yaml
