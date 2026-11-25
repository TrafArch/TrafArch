# Rail Map Generator Palette data

`tu_colors.json` is the TrafArch display palette derived from [RMG Palette](https://github.com/railmapgen/rmg-palette), by the RMG Palette contributors. This data is available under the GNU General Public License, version 3. See `GPL-3.0.txt`. The license here covers this dataset as a separate resource.

The `revision` field pins the upstream source. At that [revision](https://github.com/railmapgen/rmg-palette/tree/993a7d4dfa9277740f7a8952ed2b502309c45390/public/resources), `city-config.json` lists the cities, and `palettes/<rmg>.json` supplies the recorded colours and line names. TrafArch adds its TU city codes and CU-to-TU mappings, normalizes names, and selects unique matches to known TU rail lines. This package contains no RMG application code.

To regenerate from that exact local checkout, run from the TrafArch repository root:

```text
python -X utf8 dev/gallery/build_rail_line_palette.py --rmg-repo <path-to-rmg-palette> --revision 993a7d4dfa9277740f7a8952ed2b502309c45390
```

Add `--check` to compare the result with the bundled asset. The generator reads the TU and CU packages in immutable read-only mode. Review the changes to coverage, aliases and individual colours when updating the source commit. `assets/Line_Icon/icons.json` separately records locally supplied SVGs and approved colour overrides.
