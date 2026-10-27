#!/usr/bin/env python3
"""Copia (espejo) de los modelos que usa el juego desde Hugging Face.

Lo ejecuta GitHub Actions (.github/workflows/models.yml). Lista los archivos de
cada repositorio, descarga solo los necesarios y los deja en ./out listos para
subir a la Release "modelos" del repositorio. Licencias: ver docs/MODELOS.md.
"""
import json, os, shutil, sys, zipfile
from huggingface_hub import HfApi, hf_hub_download

OUT = "out"
os.makedirs(OUT, exist_ok=True)
api = HfApi()

# (nombre_de_salida, repo, patrones, modo)  modo: "file" = un solo archivo; "zip" = carpeta comprimida
ITEMS = json.load(open(os.path.join(os.path.dirname(__file__), "items.json")))

listing = []
for item in ITEMS:
    repo = item["repo"]
    try:
        files = list(api.list_repo_tree(repo, recursive=True))
    except Exception as e:  # noqa: BLE001
        listing.append(f"## {repo}: ERROR {e}")
        continue
    listing.append(f"## {repo}")
    for f in files:
        size = getattr(f, "size", None)
        if size is not None:
            listing.append(f"{size:>12}  {f.path}")
    if item.get("list_only"):
        continue
    wanted = []
    import fnmatch
    for f in files:
        if getattr(f, "size", None) is None:
            continue
        if any(fnmatch.fnmatch(f.path, p) for p in item["patterns"]):
            wanted.append(f.path)
    if not wanted:
        listing.append(f"!! {item['name']}: ningún archivo coincide con {item['patterns']}")
        continue
    if item["mode"] == "file":
        p = hf_hub_download(repo, wanted[0], local_dir="dl/" + item["name"])
        shutil.copy(p, os.path.join(OUT, item["name"]))
    else:
        base = "dl/" + item["name"]
        for w in wanted:
            hf_hub_download(repo, w, local_dir=base)
        zpath = os.path.join(OUT, item["name"] + ".zip")
        with zipfile.ZipFile(zpath, "w", zipfile.ZIP_STORED) as z:
            for w in wanted:
                z.write(os.path.join(base, w), w)
    listing.append(f"OK {item['name']}: {len(wanted)} archivo(s)")

open(os.path.join(OUT, "listado.txt"), "w").write("\n".join(listing) + "\n")
print("\n".join(listing))
