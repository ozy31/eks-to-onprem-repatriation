#!/usr/bin/env python3
"""Write kubeconform JSON schemas from CRDs.

Reads a JSON array of documents on stdin (yq ea -o=json '[.]' crds/*.yaml) and
writes <group>_<kind>_<version>.json into the directory given as argv[1].
Unknown fields are rejected below the root, like `kubectl --validate=strict`.
"""
import json
import pathlib
import sys


def strict(schema, root=True):
    """Walk a schema (not just any dict: CRDs have fields named "properties")."""
    if not isinstance(schema, dict):
        return schema
    if schema.get("x-kubernetes-int-or-string") or schema.get("format") == "int-or-string":
        schema.pop("format", None)
        schema.pop("type", None)
        schema["oneOf"] = [{"type": "string"}, {"type": "integer"}]
    if "properties" in schema:
        for prop in schema["properties"].values():
            strict(prop, root=False)
        if not root and "additionalProperties" not in schema \
                and not schema.get("x-kubernetes-preserve-unknown-fields"):
            schema["additionalProperties"] = False
    if isinstance(schema.get("items"), dict):
        strict(schema["items"], root=False)
    if isinstance(schema.get("additionalProperties"), dict):
        strict(schema["additionalProperties"], root=False)
    # allOf/anyOf/oneOf branches in CRDs only add constraints to fields that are
    # declared above (structural schemas), so they are left as they are.
    return schema


def main():
    out = pathlib.Path(sys.argv[1])
    docs = json.load(sys.stdin)
    count = 0
    for doc in docs:
        if not isinstance(doc, dict) or doc.get("kind") != "CustomResourceDefinition":
            continue
        spec = doc["spec"]
        for version in spec["versions"]:
            schema = version.get("schema", {}).get("openAPIV3Schema")
            if schema is None:
                continue
            name = f'{spec["group"]}_{spec["names"]["kind"]}_{version["name"]}'.lower()
            (out / f"{name}.json").write_text(json.dumps(strict(schema)))
            count += 1
    print(f"{count} schemas in {out}")


if __name__ == "__main__":
    main()
