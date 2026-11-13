# Opening dimensions and tag scale — 1.0.9 (18)

- `DOOR`, `WINDOW` and `OPENING` convert stock dimensions and frame thickness to the drawing's units. Prompts show the current unit and accept explicit suffixes such as `900mm`. Use `DOOR ReSet` to clear dimensions remembered from older versions. The scripting helpers also use drawing units for defaults.
- Stock opening types use the same dimensions as placement. Legacy stock catalog entries in non-mm files are corrected when opened. Existing door geometry and custom catalog entries are preserved. The `.archi` format remains version 6.
- New door/window tags use a compact text height equivalent to 100 mm in the model (10 cm in a cm drawing). Size labels default to Drawing units; explicit units and custom text heights remain available. Existing tags can be updated with `QUOTAINFISSI` or Properties.

See the [Italian instructions](DOOR-UNITS-IT.md) for existing drawings and the [user guide](USER-GUIDE.md) for commands.
