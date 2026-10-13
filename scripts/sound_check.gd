class_name SoundCheck
## Only play sounds that exist in Util.SFX_PATHS (network messages carry sound names).
static func ok(n: String) -> bool:
	return Util.SFX_PATHS.has(n)
