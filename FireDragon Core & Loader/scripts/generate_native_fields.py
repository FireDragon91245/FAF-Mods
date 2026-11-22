"""Extract layout facts, not engine implementations, for the native SDK.

Requires Python clang bindings and a prepared faf-re checkout (including its
WildMagic dependency patches). Release builds consume the checked-in output.
"""

from __future__ import annotations
import argparse
import json
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
ROOT_TYPES = {
    "Unit": "moho::Unit",
    "Entity": "moho::Entity",
    "Army": "moho::CArmyImpl",
    "Simulation": "moho::Sim",
    "Blueprint": "moho::RBlueprint",
    "EntityBlueprint": "moho::REntityBlueprint",
    "UnitBlueprint": "moho::RUnitBlueprint",
}


def main():
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--clang", type=Path, default=Path("H:/msys64/clang64"))
    parser.add_argument("--mingw", type=Path, default=Path("H:/msys64/mingw32"))
    args = parser.parse_args()
    os.add_dll_directory(str(args.clang / "bin"))
    from clang import cindex as c

    c.Config.set_library_file(str(args.clang / "bin/libclang.dll"))
    c.Config.set_compatibility_check(False)
    reference = args.reference.resolve()
    resource = sorted((args.clang / "lib/clang").iterdir())[-1]
    compiler = sorted((args.mingw / "include/c++").iterdir())[-1]
    options = [
        "--target=i686-w64-windows-gnu",
        "-std=c++23",
        f"-resource-dir={resource}",
        "-Wno-invalid-offsetof",
        "-I" + str(reference / "src"),
    ]
    foundation = reference / "dependencies/WildMagic3p8/Foundation"
    options += ["-I" + str(p) for p in [foundation, *foundation.rglob("*")] if p.is_dir()]
    for include in [
        compiler,
        compiler / "i686-w64-mingw32",
        compiler / "backward",
        args.mingw / "include",
    ]:
        options += ["-isystem", str(include)]
    probe = ROOT / "artifacts/native_field_probe.cpp"
    probe.parent.mkdir(exist_ok=True)
    extra = ROOT / "native/schema/headers.json"
    additional = json.loads(extra.read_text()) if extra.exists() else []
    probe.write_text(
        "\n".join(
            '#include "' + p + '"'
            for p in [
                "moho/unit/core/Unit.h",
                "moho/sim/Sim.h",
                "moho/sim/CArmyImpl.h",
                "moho/resource/blueprints/RUnitBlueprint.h",
                *additional,
            ]
        )
        + "\n"
    )
    unit = c.Index.create().parse(str(probe), args=options)
    diagnostics = [str(d) for d in unit.diagnostics if d.severity >= c.Diagnostic.Error]
    # The unrelated network linkage reuses base tail padding under GNU ABI.
    # Never export that compiler-specific layout as a verified native record.
    if any("SMsgReceiverLinkage" not in d for d in diagnostics):
        raise RuntimeError("\n".join(diagnostics))
    records = {}

    def owned(cursor):
        if not cursor.location.file:
            return False
        path = Path(cursor.location.file.name).resolve()
        return path.is_relative_to(reference / "src") or path.is_relative_to(foundation)

    for cursor in unit.cursor.walk_preorder():
        if (
            cursor.kind in (c.CursorKind.STRUCT_DECL, c.CursorKind.CLASS_DECL)
            and cursor.is_definition()
            and owned(cursor)
        ):
            name = cursor.type.get_canonical().spelling
            if name and cursor.type.get_size() > 0:
                records[name] = cursor.type
    descriptions = {}
    kind_names = {
        c.TypeKind.BOOL: "Boolean",
        c.TypeKind.FLOAT: "Float",
        c.TypeKind.DOUBLE: "Float",
        c.TypeKind.CHAR_S: "Signed",
        c.TypeKind.SCHAR: "Signed",
        c.TypeKind.SHORT: "Signed",
        c.TypeKind.INT: "Signed",
        c.TypeKind.LONG: "Signed",
        c.TypeKind.LONGLONG: "Signed",
        c.TypeKind.CHAR_U: "Unsigned",
        c.TypeKind.UCHAR: "Unsigned",
        c.TypeKind.USHORT: "Unsigned",
        c.TypeKind.UINT: "Unsigned",
        c.TypeKind.ULONG: "Unsigned",
        c.TypeKind.ULONGLONG: "Unsigned",
    }

    def name_of(type):
        name = re.sub(r"^(const |volatile )+", "", type.get_canonical().spelling)
        return (
            (name or "<unresolved>")
            .replace(str(reference).replace("\\", "/"), "$FAF_RE")
            .replace(str(reference), "$FAF_RE")
        )

    def describe(type):
        type = type.get_canonical()
        name = name_of(type)
        if name in descriptions:
            return name
        value = {
            "name": name,
            "kind": "Opaque",
            "size": max(0, type.get_size()),
            "alignment": max(1, type.get_align()),
            "complete": True,
            "element": None,
            "count": 0,
            "fields": [],
            "source": "",
        }
        descriptions[name] = value
        if type.kind in kind_names:
            value["kind"] = kind_names[type.kind]
            return name
        if type.kind == c.TypeKind.ENUM:
            value["kind"] = (
                "Unsigned"
                if type.get_declaration().enum_type.kind
                in (
                    c.TypeKind.UINT,
                    c.TypeKind.ULONG,
                    c.TypeKind.ULONGLONG,
                    c.TypeKind.UCHAR,
                    c.TypeKind.USHORT,
                )
                else "Signed"
            )
            value["enum_values"] = [
                {"name": item.spelling, "value": item.enum_value}
                for item in type.get_declaration().get_children()
                if item.kind == c.CursorKind.ENUM_CONSTANT_DECL
            ]
            return name
        if type.kind == c.TypeKind.POINTER:
            value.update(kind="Pointer", size=4, alignment=4, element=describe(type.get_pointee()))
            return name
        if type.kind == c.TypeKind.CONSTANTARRAY:
            value.update(
                kind="Array", element=describe(type.element_type), count=type.element_count
            )
            return name
        if type.kind in (c.TypeKind.FUNCTIONPROTO, c.TypeKind.FUNCTIONNOPROTO):
            value.update(complete=False, size=0)
            return name
        decl = type.get_declaration()
        if name.startswith("std::shared_ptr<"):
            # The native shared pointer is two borrowed pointer lanes, not this
            # compiler's std::shared_ptr implementation or control-block class.
            target = type.get_template_argument_type(0)
            value.update(kind="Shared", size=8, alignment=4, element=describe(target))
            # The concrete object type is carried in element; pointer storage is opaque.
            value["fields"] = [
                {
                    "name": "object",
                    "type": "void *",
                    "offset": 0,
                    "bits": 0,
                    "width": 0,
                    "declaring": name,
                    "source": "native shared pointer layout",
                },
                {
                    "name": "controlBlock",
                    "type": "void *",
                    "offset": 4,
                    "bits": 0,
                    "width": 0,
                    "declaring": name,
                    "source": "native shared pointer layout",
                },
            ]
            return name
        if not owned(decl) or type.get_size() < 0 or "SMsgReceiverLinkage" in name:
            value.update(complete=False, size=0)
            return name
        value["kind"] = (
            "String"
            if name.startswith("fa::basic_string<char") or name == "fa::string"
            else "Record"
        )
        value["source"] = (
            str(Path(decl.location.file.name).resolve().relative_to(reference)).replace("\\", "/")
            + ":"
            + str(decl.location.line)
        )
        value["bases"] = []
        value["methods"] = []
        for method in type.get_methods():
            if not owned(method):
                continue
            comment = method.raw_comment or ""
            address = re.search(r"Address:\s*(0x[0-9A-Fa-f]+)", comment)
            value["methods"].append(
                {
                    "name": method.spelling,
                    "result": name_of(method.result_type),
                    "arguments": [
                        {"name": arg.spelling, "type": name_of(arg.type)}
                        for arg in method.get_arguments()
                    ],
                    "static": method.is_static_method(),
                    "const": method.is_const_method(),
                    "virtual": method.is_virtual_method(),
                    "address": address.group(1) if address else None,
                    "source": str(
                        Path(method.location.file.name).resolve().relative_to(reference)
                    ).replace("\\", "/")
                    + ":"
                    + str(method.location.line),
                }
            )
        seen = set()

        def fields(record, base_offset=0):
            if any(method.is_virtual_method() for method in record.get_methods()):
                value["fields"].append(
                    {
                        "name": "vtable",
                        "type": "void *",
                        "offset": base_offset // 8,
                        "bits": 0,
                        "width": 0,
                        "declaring": name_of(record),
                        "source": "x86 polymorphic subobject vptr",
                    }
                )
            for field in record.get_fields():
                if not field.spelling:
                    continue
                offset = base_offset + field.get_field_offsetof()
                if offset < 0:
                    raise RuntimeError(f"Unresolved native field: {name}.{field.spelling}")
                if field.is_anonymous():
                    fields(field.type.get_canonical(), offset)
                    continue
                key = (field.spelling, offset)
                if key in seen:
                    continue
                seen.add(key)
                value["fields"].append(
                    {
                        "name": field.spelling,
                        "type": describe(field.type),
                        "offset": offset // 8,
                        "bits": offset % 8,
                        "width": field.get_bitfield_width() if field.is_bitfield() else 0,
                        "declaring": name_of(record),
                        "source": str(
                            Path(field.location.file.name).resolve().relative_to(reference)
                        ).replace("\\", "/")
                        + ":"
                        + str(field.location.line),
                    }
                )
            for child in record.get_bases():
                if owned(child.type.get_declaration()):
                    offset = base_offset + child.get_base_offsetof(record.get_declaration())
                    if offset < 0 or offset % 8:
                        raise RuntimeError(f"Unresolved native base: {name}.{child.type.spelling}")
                    value["bases"].append({"type": describe(child.type), "offset": offset // 8})
                    fields(
                        child.type.get_canonical(),
                        offset,
                    )

        fields(type)
        value["fields"].sort(key=lambda f: (f["offset"], f["name"]))
        if name.startswith(("fa::vector<", "gpg::core::FastVectorN<", "gpg::fastvector_n<")):
            value["element"] = describe(type.get_template_argument_type(0))
        return name

    # Discover all complete native records visible through the common engine
    # headers, not a manually selected set of members used by one consumer.
    for name, type in sorted(records.items()):
        describe(type)
    descriptions.setdefault(
        "void *",
        {
            "name": "void *",
            "kind": "Pointer",
            "size": 4,
            "alignment": 4,
            "complete": True,
            "element": "void",
            "count": 0,
            "fields": [],
            "source": "",
        },
    )
    descriptions.setdefault(
        "void",
        {
            "name": "void",
            "kind": "Opaque",
            "size": 0,
            "alignment": 1,
            "complete": False,
            "element": None,
            "count": 0,
            "fields": [],
            "source": "",
        },
    )
    # Shared pointer object lanes have the concrete pointed-to type in element.
    for d in descriptions.values():
        if d["kind"] == "Shared":
            d["fields"][0]["type"] = "void *"
    names = sorted(descriptions)

    def stable_id(name):
        value = 2166136261
        for byte in name.encode("utf-8"):
            value = ((value ^ byte) * 16777619) & 0xFFFFFFFF
        return value

    identifiers = {name: stable_id(name) for name in names}
    assert (
        len(set(identifiers.values())) == len(names) and 0 not in identifiers.values()
    ), "Type ID collision"
    rows = [descriptions[name] for name in names]
    for row in rows:
        row["id"] = identifiers[row["name"]]
        if row["element"] and row["element"] not in identifiers:
            raise RuntimeError(row["element"])
    for alias, canonical in ROOT_TYPES.items():
        assert canonical in descriptions and descriptions[canonical]["complete"], canonical
    expected_sizes = {
        "moho::Unit": 0x6A8,
        "moho::Entity": 0x270,
        "moho::Sim": 0xAF8,
        "moho::CArmyImpl": 0x288,
        "moho::RUnitBlueprint": 0x568,
    }
    for name, size in expected_sizes.items():
        assert descriptions[name]["size"] == size, (name, descriptions[name]["size"])
    data = {
        "profile": "FAF 3841",
        "image_sha256": "dff5e25ea82053dbbacf27ed20542fec3693b48006377581dcf7faf4ea9ec286",
        "reference_commit": subprocess.check_output(
            ["git", "-C", str(reference), "rev-parse", "HEAD"], text=True
        ).strip(),
        "root_types": {k: identifiers[v] for k, v in ROOT_TYPES.items()},
        "types": rows,
        "excluded_layouts": {
            "SMsgReceiverLinkage": "GNU/MSVC base-tail-padding layout mismatch; treated as opaque"
        },
    }
    schema = ROOT / "native/schema/faf3841.fields.json"
    schema.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(f'Generated {len(rows)} types, {sum(len(r["fields"]) for r in rows)} fields')
    for alias, canonical in ROOT_TYPES.items():
        print(alias, len(descriptions[canonical]["fields"]))


if __name__ == "__main__":
    main()
