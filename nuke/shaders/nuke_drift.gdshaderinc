// Dérive au vent du champignon (nuke/nuke_mushroom.gd, _drift_profile), partagée par le rendu volumétrique
// (nuke_mushroom_volume.gdshader) et le rendu par maillage (nuke_mushroom.gdshader).
// Déplacement horizontal (repère local normalisé : sommet final = 1) en fonction de la hauteur y, échantillonné en
// 32 hauteurs régulières de 0 à drift_top (interpolation linéaire, constant au-delà). Il vient du profil vertical du
// vent réel (GFS) : chaque altitude part dans sa propre direction, à sa propre vitesse.

uniform vec3 drift_profile[32];
uniform float drift_top = 1.4;

vec3 nuke_drift(float y) {
	float f = clamp(y / max(drift_top, 1e-4), 0.0, 1.0) * 31.0;
	int i = min(int(f), 30);
	return mix(drift_profile[i], drift_profile[i + 1], f - float(i));
}
