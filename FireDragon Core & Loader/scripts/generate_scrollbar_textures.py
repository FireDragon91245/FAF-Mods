"""Rotate FAF's vertical scrollbar art for the shared horizontal scrollbar."""
import argparse
import io
from pathlib import Path
import zipfile

from PIL import Image


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path, help="FAF gamedata/textures.nx2")
    args = parser.parse_args()
    output = Path(__file__).resolve().parents[1] / "src/textures/ui/scrollbar"
    output.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(args.archive) as archive:
        for source, target in [("back_scr_mid.dds", "horizontal-back.dds"),
                               ("bar-mid_scr_up.dds", "horizontal-thumb.dds")]:
            image = Image.open(io.BytesIO(archive.read("textures/ui/common/SCROLLBAR_VERT/" + source)))
            image.transpose(Image.Transpose.ROTATE_90).save(output / target)


if __name__ == "__main__":
    main()
