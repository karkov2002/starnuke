// Lumière des flashs nucléaires, injectée dans le sol (earth_surface.gdshader) et les nuages (cloud_volume.gdshader).
// Les lumières Godot n'y conviennent pas : le sol a un light() propre au soleil, les nuages sont unshaded.
// À inclure après cloud_density.gdshaderinc. Les uniforms sont alimentés à chaque image par nuke/nuke_flash_fx.gd ;
// sans flash actif (nuke_flash_count = 0), les fonctions retournent 0 immédiatement.
//
// Positions en km dans le repère de la planète. Flux en « soleils » (1 = éclairement solaire) à la distance de
// référence NUKE_FLASH_REF_KM, décroissant en 1/d². Le sol reçoit flux × cos(incidence) : un point ne voit le flash
// que s'il est au-dessus de son horizon local (exact sur une sphère), plus une petite part diffusée par l'air.
#ifndef NUKE_FLASH_INC
#define NUKE_FLASH_INC

const int NUKE_MAX_FLASHES = 4;
const float NUKE_FLASH_REF_KM = 400.0;
// Plafond de l'éclairement (soleils) près de la boule de feu : reste dans le format flottant 16 bits du rendu.
const float NUKE_FLASH_MAX = 2000.0;

uniform int nuke_flash_count = 0;
uniform vec3 nuke_flash_pos_km[4];
uniform float nuke_flash_flux[4];
uniform vec3 nuke_flash_color : source_color = vec3(1.0, 0.9, 0.78);
// Lumière diffusée par l'atmosphère autour du flash (part du flux direct, portée en km).
uniform float nuke_flash_sky_fraction = 0.03;
uniform float nuke_flash_sky_range_km = 60.0;
// Énergie d'un « soleil » sur le sol, comme la DirectionalLight Sun (light_energy = 2).
uniform float nuke_flash_ground_gain = 2.0;

// Éclairement (soleils) reçu par le sol au point p (normale n) : direct × ombre des nuages (4 échantillons sur le
// segment sol → flash) + diffusé.
float nuke_flash_ground(vec3 p, vec3 n, CloudAdvection adv) {
	float total = 0.0;
	for (int i = 0; i < NUKE_MAX_FLASHES; i++) {
		if (i >= nuke_flash_count) {
			break;
		}
		vec3 to = nuke_flash_pos_km[i] - p;
		float d2 = max(dot(to, to), 0.01);
		float d = sqrt(d2);
		float e = nuke_flash_flux[i] * NUKE_FLASH_REF_KM * NUKE_FLASH_REF_KM / d2;
		float direct = max(dot(n, to / d), 0.0);
		float sky = nuke_flash_sky_fraction * exp(-d / nuke_flash_sky_range_km);
		if (e * (direct + sky) < 1e-4) {
			continue;
		}
		if (direct > 0.0) {
			float od = 0.0;
			for (int j = 0; j < 4; j++) {
				od += cloud_density(p + to * ((float(j) + 0.5) / 4.0), TIME, false, 2.0, adv);
			}
			direct *= exp(-cloud_extinction_per_km * od * d / 4.0);
		}
		total += e * (direct + sky);
	}
	return min(total, NUKE_FLASH_MAX);
}

// Éclairement (soleils) reçu par un point du volume nuageux : 1/d², nul si la Terre s'interpose, auto-ombrage par une
// marche vers le flash (pas doublés), même approximation de la diffusion multiple que pour le soleil.
float nuke_flash_volume(vec3 p, float lod, CloudAdvection adv, float multiple_scattering) {
	float total = 0.0;
	for (int i = 0; i < NUKE_MAX_FLASHES; i++) {
		if (i >= nuke_flash_count) {
			break;
		}
		vec3 to = nuke_flash_pos_km[i] - p;
		float d2 = max(dot(to, to), 0.01);
		float d = sqrt(d2);
		float e = nuke_flash_flux[i] * NUKE_FLASH_REF_KM * NUKE_FLASH_REF_KM / d2;
		if (e < 1e-3) {
			continue;
		}
		vec3 l = to / d;
		// Masqué par la Terre : le segment nuage → flash passe sous la surface (courbure, au-delà de l'horizon).
		vec3 closest = p + l * clamp(-dot(p, l), 0.0, d);
		if (dot(closest, closest) < CLOUD_PLANET_RADIUS_KM * CLOUD_PLANET_RADIUS_KM) {
			continue;
		}
		float od = 0.0;
		float tl = 0.0;
		float s = 0.3;
		for (int j = 0; j < 4; j++) {
			float step_km = min(s, d - tl);
			if (step_km <= 0.0) {
				break;
			}
			od += cloud_density(p + l * (tl + 0.5 * step_km), TIME, false, lod + 1.0, adv) * step_km;
			tl += step_km;
			s *= 2.0;
		}
		float beer = exp(-cloud_extinction_per_km * od);
		total += e * max(beer, multiple_scattering * exp(-0.25 * cloud_extinction_per_km * od));
	}
	return min(total, NUKE_FLASH_MAX);
}

#endif
