#include "voxelcore.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <queue>
#include <unordered_set>

using namespace godot;

// ------------------------------------------------------------------ helpers
static const int DIRS[6][3] = { { 1, 0, 0 }, { -1, 0, 0 }, { 0, 1, 0 }, { 0, -1, 0 }, { 0, 0, 1 }, { 0, 0, -1 } };

static inline void face_axes(int d, int &na, int &ua, int &va) {
	if (d < 2) {
		na = 0;
		ua = 2;
		va = 1;
	} else if (d < 4) {
		na = 1;
		ua = 0;
		va = 2;
	} else {
		na = 2;
		ua = 0;
		va = 1;
	}
}

static inline int floordiv(int a, int b) {
	return a >= 0 ? a / b : -((-a + b - 1) / b);
}

static inline uint32_t ihash(int x, int y, int z, uint32_t s) {
	uint32_t h = (uint32_t)x * 374761393u + (uint32_t)y * 668265263u + (uint32_t)z * 1440662683u + s * 1274126177u;
	h = (h ^ (h >> 13)) * 1274126177u;
	return h ^ (h >> 16);
}

static inline float hfrac(int x, int y, int z, uint32_t s) {
	return (ihash(x, y, z, s) & 0xFFFF) / 65536.0f;
}

static inline int64_t pkey(int x, int y, int z) {
	return ((int64_t)(x + 1048576) << 42) | ((int64_t)(y + 1048576) << 21) | (int64_t)(z + 1048576);
}

static inline int vs_index(float vs) {
	return (int)std::lround(std::log2(vs) + 5.0);
}

VxTables::VxTables() {
	memset(solid, 0, sizeof(solid));
	memset(water, 0, sizeof(water));
	memset(hard, 0, sizeof(hard));
	solid[255] = 1; // unknown / unloaded: treated as solid, never meshed against
	hard[255] = 255;
}

static void tables_from(VxTables &t, const PackedByteArray &solid, const PackedByteArray &water, const PackedByteArray &hard, int deep) {
	for (int i = 0; i < 256; i++) {
		t.solid[i] = i < solid.size() ? solid[i] : 0;
		t.water[i] = i < water.size() ? water[i] : 0;
		t.hard[i] = i < hard.size() ? hard[i] : 0;
	}
	t.solid[0] = 0;
	t.solid[255] = 1;
	t.water[255] = 0;
	t.hard[255] = 255;
	t.deep = (uint8_t)deep;
}

// ------------------------------------------------------------------ greedy mesher
// b has one voxel of padding on every side; interior = [1, X-1) etc. Positions are offset + interior * vs.
static void greedy_mesh(const VxBuf &b, const VxTables &t, bool water_pass, bool use_ao, float vs, const Vector3 &off, VxMesh &out) {
	const int N[3] = { b.X - 2, b.Y - 2, b.Z - 2 };
	if (N[0] <= 0 || N[1] <= 0 || N[2] <= 0) {
		return;
	}
	const uint8_t vsi = (uint8_t)vs_index(vs);
	std::vector<uint32_t> mask;
	for (int d = 0; d < 6; d++) {
		int na, ua, va;
		face_axes(d, na, ua, va);
		const int dx = DIRS[d][0], dy = DIRS[d][1], dz = DIRS[d][2];
		const int S = N[na], W = N[ua], H = N[va];
		mask.assign((size_t)W * H, 0);
		int tu[3] = { 0, 0, 0 }, tv[3] = { 0, 0, 0 };
		tu[ua] = 1;
		tv[va] = 1;
		// winding: reverse when U x V points along the face normal
		int cr[3] = { tu[1] * tv[2] - tu[2] * tv[1], tu[2] * tv[0] - tu[0] * tv[2], tu[0] * tv[1] - tu[1] * tv[0] };
		const bool facing = (cr[0] * dx + cr[1] * dy + cr[2] * dz) > 0;
		for (int s = 0; s < S; s++) {
			bool any = false;
			for (int iu = 0; iu < W; iu++) {
				for (int iv = 0; iv < H; iv++) {
					int c[3];
					c[na] = s;
					c[ua] = iu;
					c[va] = iv;
					const int x = c[0] + 1, y = c[1] + 1, z = c[2] + 1;
					const uint8_t v = b.at(x, y, z);
					uint32_t key = 0;
					const bool src = water_pass ? t.water[v] : (t.solid[v] && v != 255);
					if (src) {
						const int nx = x + dx, ny = y + dy, nz = z + dz;
						const uint8_t nb = b.at(nx, ny, nz);
						const bool occl = water_pass ? (t.solid[nb] || t.water[nb]) : (bool)t.solid[nb];
						if (!occl) {
							if (!use_ao) {
								key = (uint32_t)v | (0xFFu << 8) | (1u << 24);
							} else {
								uint32_t a[4];
								for (int k = 0; k < 4; k++) {
									const int su = (k == 0 || k == 3) ? -1 : 1;
									const int sv = (k == 0 || k == 1) ? -1 : 1;
									const int s1 = t.solid[b.at(nx + su * tu[0], ny + su * tu[1], nz + su * tu[2])] ? 1 : 0;
									const int s2 = t.solid[b.at(nx + sv * tv[0], ny + sv * tv[1], nz + sv * tv[2])] ? 1 : 0;
									const int cc = t.solid[b.at(nx + su * tu[0] + sv * tv[0], ny + su * tu[1] + sv * tv[1], nz + su * tu[2] + sv * tv[2])] ? 1 : 0;
									a[k] = (s1 && s2) ? 0 : (uint32_t)(3 - (s1 + s2 + cc));
								}
								key = (uint32_t)v | (a[0] << 8) | (a[1] << 10) | (a[2] << 12) | (a[3] << 14) | (1u << 24);
								if (!(a[0] == a[1] && a[1] == a[2] && a[2] == a[3])) {
									key |= 1u << 20;
									if (a[0] == a[1] && a[3] == a[2]) {
										key |= 1u << 21;
									}
									if (a[0] == a[3] && a[1] == a[2]) {
										key |= 1u << 22;
									}
								}
							}
							any = true;
						}
					}
					mask[(size_t)iu * H + iv] = key;
				}
			}
			if (!any) {
				continue;
			}
			const float plane = (float)(s + ((d % 2 == 0) ? 1 : 0));
			for (int iv = 0; iv < H; iv++) {
				int iu = 0;
				while (iu < W) {
					const uint32_t key = mask[(size_t)iu * H + iv];
					if (!key) {
						iu++;
						continue;
					}
					int w = 1, h = 1;
					const bool uni = ((key >> 20) & 1) == 0;
					if (uni || ((key >> 21) & 1)) {
						while (iu + w < W && mask[(size_t)(iu + w) * H + iv] == key) {
							w++;
						}
					}
					if (uni || ((key >> 22) & 1)) {
						while (iv + h < H) {
							bool ok = true;
							for (int k = 0; k < w; k++) {
								if (mask[(size_t)(iu + k) * H + iv + h] != key) {
									ok = false;
									break;
								}
							}
							if (!ok) {
								break;
							}
							h++;
						}
					}
					for (int a2 = 0; a2 < w; a2++) {
						for (int b2 = 0; b2 < h; b2++) {
							mask[(size_t)(iu + a2) * H + iv + b2] = 0;
						}
					}
					// emit quad
					const int base = (int)(out.pos.size() / 3);
					const float cu[4] = { (float)iu, (float)(iu + w), (float)(iu + w), (float)iu };
					const float cv[4] = { (float)iv, (float)iv, (float)(iv + h), (float)(iv + h) };
					uint32_t ao[4];
					for (int k = 0; k < 4; k++) {
						ao[k] = (key >> (8 + 2 * k)) & 3;
						float p[3];
						p[na] = plane;
						p[ua] = cu[k];
						p[va] = cv[k];
						out.pos.push_back(off.x + p[0] * vs);
						out.pos.push_back(off.y + p[1] * vs);
						out.pos.push_back(off.z + p[2] * vs);
						out.nrm.push_back((float)dx);
						out.nrm.push_back((float)dy);
						out.nrm.push_back((float)dz);
						out.cus.push_back((uint8_t)(key & 0xFF));
						out.cus.push_back((uint8_t)ao[k]);
						out.cus.push_back(vsi);
						out.cus.push_back(255);
					}
					static const int TA[6] = { 0, 1, 2, 0, 2, 3 };
					static const int TB[6] = { 0, 1, 3, 1, 2, 3 };
					const bool flip = (ao[0] + ao[2]) < (ao[1] + ao[3]);
					const int *tri = flip ? TB : TA;
					int o[6];
					if (facing) {
						o[0] = tri[0];
						o[1] = tri[2];
						o[2] = tri[1];
						o[3] = tri[3];
						o[4] = tri[5];
						o[5] = tri[4];
					} else {
						for (int k = 0; k < 6; k++) {
							o[k] = tri[k];
						}
					}
					for (int k = 0; k < 6; k++) {
						out.idx.push_back(base + o[k]);
					}
					out.quads++;
					iu += w;
				}
			}
		}
	}
}

static void collision_mesh(const VxBuf &b, const VxTables &t, float vs, const Vector3 &off, std::vector<float> &tri) {
	const int N[3] = { b.X - 2, b.Y - 2, b.Z - 2 };
	std::vector<uint8_t> mask;
	for (int d = 0; d < 6; d++) {
		int na, ua, va;
		face_axes(d, na, ua, va);
		const int dx = DIRS[d][0], dy = DIRS[d][1], dz = DIRS[d][2];
		const int S = N[na], W = N[ua], H = N[va];
		mask.assign((size_t)W * H, 0);
		int tu[3] = { 0, 0, 0 }, tv[3] = { 0, 0, 0 };
		tu[ua] = 1;
		tv[va] = 1;
		int cr[3] = { tu[1] * tv[2] - tu[2] * tv[1], tu[2] * tv[0] - tu[0] * tv[2], tu[0] * tv[1] - tu[1] * tv[0] };
		const bool facing = (cr[0] * dx + cr[1] * dy + cr[2] * dz) > 0;
		for (int s = 0; s < S; s++) {
			bool any = false;
			for (int iu = 0; iu < W; iu++) {
				for (int iv = 0; iv < H; iv++) {
					int c[3];
					c[na] = s;
					c[ua] = iu;
					c[va] = iv;
					const int x = c[0] + 1, y = c[1] + 1, z = c[2] + 1;
					const uint8_t v = b.at(x, y, z);
					uint8_t m = 0;
					if (t.solid[v] && v != 255 && !t.solid[b.at(x + dx, y + dy, z + dz)]) {
						m = 1;
						any = true;
					}
					mask[(size_t)iu * H + iv] = m;
				}
			}
			if (!any) {
				continue;
			}
			const float plane = (float)(s + ((d % 2 == 0) ? 1 : 0));
			for (int iv = 0; iv < H; iv++) {
				int iu = 0;
				while (iu < W) {
					if (!mask[(size_t)iu * H + iv]) {
						iu++;
						continue;
					}
					int w = 1, h = 1;
					while (iu + w < W && mask[(size_t)(iu + w) * H + iv]) {
						w++;
					}
					while (iv + h < H) {
						bool ok = true;
						for (int k = 0; k < w; k++) {
							if (!mask[(size_t)(iu + k) * H + iv + h]) {
								ok = false;
								break;
							}
						}
						if (!ok) {
							break;
						}
						h++;
					}
					for (int a2 = 0; a2 < w; a2++) {
						for (int b2 = 0; b2 < h; b2++) {
							mask[(size_t)(iu + a2) * H + iv + b2] = 0;
						}
					}
					float P[4][3];
					const float cu[4] = { (float)iu, (float)(iu + w), (float)(iu + w), (float)iu };
					const float cv[4] = { (float)iv, (float)iv, (float)(iv + h), (float)(iv + h) };
					for (int k = 0; k < 4; k++) {
						float p[3];
						p[na] = plane;
						p[ua] = cu[k];
						p[va] = cv[k];
						P[k][0] = off.x + p[0] * vs;
						P[k][1] = off.y + p[1] * vs;
						P[k][2] = off.z + p[2] * vs;
					}
					static const int TA[6] = { 0, 1, 2, 0, 2, 3 };
					static const int TF[6] = { 0, 2, 1, 0, 3, 2 };
					const int *o = facing ? TF : TA;
					for (int k = 0; k < 6; k++) {
						tri.push_back(P[o[k]][0]);
						tri.push_back(P[o[k]][1]);
						tri.push_back(P[o[k]][2]);
					}
					iu += w;
				}
			}
		}
	}
}

// majority 2x2x2 down-sample of painted values (solid wins at >= 4 of 8, else water)
static void downsample2(const VxBuf &src, VxBuf &dst, const VxTables &t) {
	dst.alloc(src.X / 2, src.Y / 2, src.Z / 2, 0);
	uint8_t vals[8];
	for (int i = 0; i < dst.X; i++) {
		for (int j = 0; j < dst.Y; j++) {
			for (int k = 0; k < dst.Z; k++) {
				int n = 0, nw = 0;
				uint8_t wv = 0;
				bool unknown = false;
				for (int a = 0; a < 2; a++) {
					for (int b = 0; b < 2; b++) {
						for (int c = 0; c < 2; c++) {
							const uint8_t v = src.at(2 * i + a, 2 * j + b, 2 * k + c);
							if (v == 0) {
								continue;
							}
							if (v == 255) {
								unknown = true;
								continue;
							}
							if (t.water[v]) {
								nw++;
								if (!wv || (v >> 2) != (wv >> 2)) {
									wv = std::max(wv, v);
								}
								continue;
							}
							if (t.solid[v]) {
								vals[n++] = v;
							}
						}
					}
				}
				uint8_t out = 0;
				if (unknown) {
					out = 255;
				} else if (n >= 4) {
					int bc = 0;
					uint8_t best = vals[0];
					for (int q = 0; q < n; q++) {
						int cnt = 0;
						for (int r = 0; r < n; r++) {
							cnt += vals[r] == vals[q];
						}
						if (cnt >= bc) {
							bc = cnt;
							best = vals[q];
						}
					}
					out = best;
				} else if (n + nw >= 4 && nw > 0) {
					out = wv;
				}
				dst.ref(i, j, k) = out;
			}
		}
	}
}

static Dictionary mesh_to_dict(const VxMesh &m) {
	Dictionary d;
	if (m.quads == 0) {
		return d;
	}
	const int nv = (int)(m.pos.size() / 3);
	PackedVector3Array pos, nrm;
	pos.resize(nv);
	nrm.resize(nv);
	Vector3 *pw = pos.ptrw();
	Vector3 *nw = nrm.ptrw();
	for (int i = 0; i < nv; i++) {
		pw[i] = Vector3(m.pos[i * 3], m.pos[i * 3 + 1], m.pos[i * 3 + 2]);
		nw[i] = Vector3(m.nrm[i * 3], m.nrm[i * 3 + 1], m.nrm[i * 3 + 2]);
	}
	PackedByteArray cus;
	cus.resize((int64_t)m.cus.size());
	memcpy(cus.ptrw(), m.cus.data(), m.cus.size());
	PackedInt32Array idx;
	idx.resize((int64_t)m.idx.size());
	memcpy(idx.ptrw(), m.idx.data(), m.idx.size() * sizeof(int32_t));
	d["pos"] = pos;
	d["nrm"] = nrm;
	d["cus"] = cus;
	d["idx"] = idx;
	d["quads"] = m.quads;
	return d;
}

// mesh a padded full-res buffer (padding = 1 << lod) at the requested LOD
static Dictionary mesh_buffer_lod(VxBuf &full, const VxTables &t, int lod, bool water, bool ao, float vs, const Vector3 &off) {
	VxBuf *cur = &full;
	VxBuf a, b2;
	for (int l = 0; l < lod; l++) {
		VxBuf &dst = (l % 2 == 0) ? a : b2;
		downsample2(*cur, dst, t);
		cur = &dst;
	}
	VxMesh m;
	greedy_mesh(*cur, t, water, ao, vs * (float)(1 << lod), off, m);
	return mesh_to_dict(m);
}

// ------------------------------------------------------------------ variants for placed voxels
static uint8_t pattern_variant(int pattern, int mat, int x, int y, int z) {
	switch (pattern) {
		case 1: // uniform
			return 0;
		case 2: { // running bond: rows 2 voxels high, blocks 3 long, darker joints
			const int row = floordiv(y, 2);
			const int along = x + z + (row & 1) * 2;
			const int blk = floordiv(along, 3);
			if (floordiv(y, 1) % 2 == 0 && ((along % 3 + 3) % 3) == 0) {
				return 3;
			}
			return (uint8_t)(ihash(row, blk, 0, 51) % 3);
		}
		case 3: // stripes
			return (uint8_t)((floordiv(y, 2) & 1) ? 1 : 0);
		case 4: // checker
			return (uint8_t)(((x + y + z) & 1) ? 2 : 0);
		case 5: // random mix
			return (uint8_t)(ihash(x, y, z, 77) % 4);
		default: { // natural clumps
			const uint8_t v = (uint8_t)(ihash(floordiv(x, 2), floordiv(y, 2), floordiv(z, 2), 61 + mat) % 3);
			return hfrac(x, y, z, 62) < 0.02f ? 3 : v;
		}
	}
}

// ------------------------------------------------------------------ carving / islands (shared)
struct CarveNode {
	float s;
	int64_t key;
	int x, y, z;
	bool operator>(const CarveNode &o) const { return s > o.s || (s == o.s && key > o.key); }
};

static void carve_cluster_impl(VxAccess &acc, const VxTables &t, Vector3i at, Vector3i nrm, int count, int max_hard, int seed, float jitter,
		Vector3i lo, Vector3i hi, std::vector<int32_t> &removed) {
	const bool bounded = lo.x <= hi.x;
	auto mineable = [&](uint8_t v) { return v != 0 && v != 255 && t.solid[v] && t.hard[v] <= max_hard; };
	auto inb = [&](int x, int y, int z) {
		return !bounded || (x >= lo.x && x <= hi.x && y >= lo.y && y <= hi.y && z >= lo.z && z <= hi.z);
	};
	if (!inb(at.x, at.y, at.z) || !mineable(acc.vget(at.x, at.y, at.z))) {
		return;
	}
	const float r = std::cbrt((float)count);
	const float bias = 0.42f * r;
	const float cx = at.x + 0.5f - nrm.x * bias, cy = at.y + 0.5f - nrm.y * bias, cz = at.z + 0.5f - nrm.z * bias;
	std::priority_queue<CarveNode, std::vector<CarveNode>, std::greater<CarveNode>> pq;
	std::unordered_set<int64_t> seen;
	seen.insert(pkey(at.x, at.y, at.z));
	pq.push({ 0.0f, pkey(at.x, at.y, at.z), at.x, at.y, at.z });
	int n = 0;
	while (!pq.empty() && n < count) {
		CarveNode c = pq.top();
		pq.pop();
		const uint8_t v = acc.vget(c.x, c.y, c.z);
		if (!mineable(v)) {
			continue;
		}
		acc.vset(c.x, c.y, c.z, 0);
		removed.push_back(c.x);
		removed.push_back(c.y);
		removed.push_back(c.z);
		removed.push_back(v);
		n++;
		for (int d = 0; d < 6; d++) {
			const int x = c.x + DIRS[d][0], y = c.y + DIRS[d][1], z = c.z + DIRS[d][2];
			const int64_t k = pkey(x, y, z);
			if (seen.count(k) || !inb(x, y, z)) {
				continue;
			}
			seen.insert(k);
			const uint8_t v2 = acc.vget(x, y, z);
			if (!mineable(v2)) {
				continue;
			}
			const float ddx = x + 0.5f - cx, ddy = y + 0.5f - cy, ddz = z + 0.5f - cz;
			// harder material resists: prefer softer neighbours a little
			const float s = std::sqrt(ddx * ddx + ddy * ddy + ddz * ddz) + jitter * r * 0.5f * hfrac(x, y, z, (uint32_t)seed) +
					0.15f * (float)t.hard[v2];
			pq.push({ s, k, x, y, z });
		}
	}
}

struct Island {
	std::vector<int32_t> vox; // x, y, z, v
};

static void find_islands_impl(VxAccess &acc, const VxTables &t, Vector3i lo, Vector3i hi, int limit, std::vector<Island> &out) {
	std::unordered_map<int64_t, uint8_t> state; // 1 visiting, 2 anchored, 3 island
	std::vector<int32_t> comp;
	std::vector<int64_t> keys;
	std::vector<int32_t> queue;
	for (int x = lo.x; x <= hi.x; x++) {
		for (int y = lo.y; y <= hi.y; y++) {
			for (int z = lo.z; z <= hi.z; z++) {
				const uint8_t v0 = acc.vget(x, y, z);
				if (!t.solid[v0] || v0 == 255) {
					continue;
				}
				const int64_t k0 = pkey(x, y, z);
				if (state.count(k0)) {
					continue;
				}
				comp.clear();
				keys.clear();
				queue.clear();
				bool anchored = acc.anchored(x, y, z, v0);
				state[k0] = 1;
				keys.push_back(k0);
				comp.push_back(x);
				comp.push_back(y);
				comp.push_back(z);
				comp.push_back(v0);
				queue.push_back(x);
				queue.push_back(y);
				queue.push_back(z);
				size_t qi = 0;
				while (!anchored && qi < queue.size()) {
					const int cx = queue[qi], cy = queue[qi + 1], cz = queue[qi + 2];
					qi += 3;
					for (int d = 0; d < 6 && !anchored; d++) {
						const int nx = cx + DIRS[d][0], ny = cy + DIRS[d][1], nz = cz + DIRS[d][2];
						const uint8_t v = acc.vget(nx, ny, nz);
						if (v == 0 || !t.solid[v]) {
							continue;
						}
						if (v == 255) {
							anchored = true;
							break;
						}
						const int64_t k = pkey(nx, ny, nz);
						auto it = state.find(k);
						if (it != state.end()) {
							if (it->second == 2) {
								anchored = true;
							}
							continue;
						}
						state[k] = 1;
						keys.push_back(k);
						comp.push_back(nx);
						comp.push_back(ny);
						comp.push_back(nz);
						comp.push_back(v);
						queue.push_back(nx);
						queue.push_back(ny);
						queue.push_back(nz);
						if (acc.anchored(nx, ny, nz, v) || (int)keys.size() > limit) {
							anchored = true;
						}
					}
				}
				const uint8_t mark = anchored ? 2 : 3;
				for (int64_t k : keys) {
					state[k] = mark;
				}
				if (!anchored) {
					Island isl;
					isl.vox = comp;
					out.push_back(std::move(isl));
				}
			}
		}
	}
}

// ------------------------------------------------------------------ VoxelVolume
class VolumeAccess : public VxAccess {
public:
	VoxelVolume *v;
	explicit VolumeAccess(VoxelVolume *p) :
			v(p) {}
	uint8_t vget(int x, int y, int z) override { return v->get(x, y, z); }
	void vset(int x, int y, int z, uint8_t val) override { v->set(x, y, z, val); }
	bool anchored(int x, int y, int z, uint8_t val) override {
		Vector2i r = v->get_chunk_range(floordiv(x, 128), floordiv(z, 128));
		return r.y == 0 || y <= r.x + 1;
	}
};

void VoxelVolume::setup(Vector3 p_origin, float p_vs, int p_chunk) {
	origin = p_origin;
	vs = p_vs;
	cs = p_chunk;
}

void VoxelVolume::set_tables(PackedByteArray solid, PackedByteArray water, PackedByteArray hard, int deep) {
	tables_from(t, solid, water, hard, deep);
}

VoxelVolume::Chunk *VoxelVolume::find(int cx, int cz) {
	const int64_t k = ((int64_t)cx << 32) ^ (uint32_t)cz;
	if (k == last_key) {
		return last;
	}
	auto it = chunks.find(k);
	last_key = k;
	last = it == chunks.end() ? nullptr : &it->second;
	return last;
}

void VoxelVolume::load_chunk(int cx, int cz, int y_lo, int cy, PackedByteArray data) {
	Chunk c;
	c.y_lo = y_lo;
	c.cy = cy;
	c.d.resize((size_t)cs * cy * cs);
	const size_t n = std::min((size_t)data.size(), c.d.size());
	memcpy(c.d.data(), data.ptr(), n);
	const int64_t k = ((int64_t)cx << 32) ^ (uint32_t)cz;
	chunks[k] = std::move(c);
	last_key = INT64_MIN;
	last = nullptr;
}

bool VoxelVolume::has_chunk(int cx, int cz) {
	return find(cx, cz) != nullptr;
}

void VoxelVolume::unload_chunk(int cx, int cz) {
	chunks.erase(((int64_t)cx << 32) ^ (uint32_t)cz);
	last_key = INT64_MIN;
	last = nullptr;
}

PackedByteArray VoxelVolume::get_chunk_data(int cx, int cz) {
	PackedByteArray out;
	Chunk *c = find(cx, cz);
	if (!c) {
		return out;
	}
	out.resize((int64_t)c->d.size());
	memcpy(out.ptrw(), c->d.data(), c->d.size());
	return out;
}

Vector2i VoxelVolume::get_chunk_range(int cx, int cz) {
	Chunk *c = find(cx, cz);
	return c ? Vector2i(c->y_lo, c->cy) : Vector2i(0, 0);
}

uint8_t VoxelVolume::get(int x, int y, int z) {
	const int cx = floordiv(x, cs), cz = floordiv(z, cs);
	Chunk *c = find(cx, cz);
	if (!c) {
		return 255;
	}
	const int ly = y - c->y_lo;
	if (ly < 0) {
		return t.deep;
	}
	if (ly >= c->cy) {
		return 0;
	}
	return c->d[((size_t)(x - cx * cs) * c->cy + ly) * cs + (z - cz * cs)];
}

void VoxelVolume::grow(Chunk &c, int gy) {
	int new_lo = c.y_lo, new_hi = c.y_lo + c.cy;
	if (gy < new_lo) {
		new_lo = gy - ((new_lo - gy) % 32 ? 32 - (new_lo - gy) % 32 : 0);
		new_lo = std::min(new_lo, c.y_lo - 32);
	}
	if (gy >= new_hi) {
		new_hi = gy + 32;
	}
	const int ncy = new_hi - new_lo;
	std::vector<uint8_t> nd((size_t)cs * ncy * cs, 0);
	const int shift = c.y_lo - new_lo;
	for (int x = 0; x < cs; x++) {
		for (int y = 0; y < ncy; y++) {
			const int oy = y - shift;
			uint8_t *dst = &nd[((size_t)x * ncy + y) * cs];
			if (oy < 0) {
				memset(dst, t.deep, cs);
			} else if (oy < c.cy) {
				memcpy(dst, &c.d[((size_t)x * c.cy + oy) * cs], cs);
			}
		}
	}
	c.d.swap(nd);
	c.y_lo = new_lo;
	c.cy = ncy;
}

bool VoxelVolume::set(int x, int y, int z, uint8_t v) {
	const int cx = floordiv(x, cs), cz = floordiv(z, cs);
	Chunk *c = find(cx, cz);
	if (!c) {
		return false;
	}
	int ly = y - c->y_lo;
	if (ly < 0 || ly >= c->cy) {
		if (v == 0 && ly >= c->cy) {
			return true;
		}
		grow(*c, y);
		ly = y - c->y_lo;
	}
	c->d[((size_t)(x - cx * cs) * c->cy + ly) * cs + (z - cz * cs)] = v;
	return true;
}

void VoxelVolume::extract(int x0, int y0, int z0, int X, int Y, int Z, VxBuf &b) {
	b.alloc(X, Y, Z, 0);
	for (int i = 0; i < X; i++) {
		const int x = x0 + i;
		const int cx = floordiv(x, cs);
		const int lx = x - cx * cs;
		for (int k = 0; k < Z; k++) {
			const int z = z0 + k;
			const int cz = floordiv(z, cs);
			Chunk *c = find(cx, cz);
			const int lz = z - cz * cs;
			for (int j = 0; j < Y; j++) {
				const int y = y0 + j;
				uint8_t v;
				if (!c) {
					v = 255;
				} else {
					const int ly = y - c->y_lo;
					if (ly < 0) {
						v = t.deep;
					} else if (ly >= c->cy) {
						v = 0;
					} else {
						v = c->d[((size_t)lx * c->cy + ly) * cs + lz];
					}
				}
				b.ref(i, j, k) = v;
			}
		}
	}
}

int VoxelVolume::get_voxel(Vector3i p) {
	return get(p.x, p.y, p.z);
}

void VoxelVolume::set_voxel(Vector3i p, int v) {
	set(p.x, p.y, p.z, (uint8_t)v);
}

Dictionary VoxelVolume::mesh_region(Vector3i lo, Vector3i size, int lod, bool water, bool ao, Vector3 offset) {
	const int f = 1 << lod;
	VxBuf b;
	extract(lo.x - f, lo.y - f, lo.z - f, size.x + 2 * f, size.y + 2 * f, size.z + 2 * f, b);
	return mesh_buffer_lod(b, t, lod, water, ao, vs, offset);
}

PackedVector3Array VoxelVolume::collision_region(Vector3i lo, Vector3i size, Vector3 offset) {
	VxBuf b;
	extract(lo.x - 1, lo.y - 1, lo.z - 1, size.x + 2, size.y + 2, size.z + 2, b);
	std::vector<float> tri;
	collision_mesh(b, t, vs, offset, tri);
	PackedVector3Array out;
	const int n = (int)(tri.size() / 3);
	out.resize(n);
	Vector3 *w = out.ptrw();
	for (int i = 0; i < n; i++) {
		w[i] = Vector3(tri[i * 3], tri[i * 3 + 1], tri[i * 3 + 2]);
	}
	return out;
}

static Dictionary dda(VxAccess &acc, const VxTables &t, Vector3 p, Vector3 d, float max_t, bool hit_water) {
	Dictionary r;
	r["hit"] = false;
	if (d.length_squared() < 1e-12) {
		return r;
	}
	d = d.normalized();
	int ix = (int)std::floor(p.x), iy = (int)std::floor(p.y), iz = (int)std::floor(p.z);
	const int sx = d.x > 0 ? 1 : -1, sy = d.y > 0 ? 1 : -1, sz = d.z > 0 ? 1 : -1;
	const double inf = 1e30;
	const double tdx = std::fabs(d.x) > 1e-9 ? 1.0 / std::fabs(d.x) : inf;
	const double tdy = std::fabs(d.y) > 1e-9 ? 1.0 / std::fabs(d.y) : inf;
	const double tdz = std::fabs(d.z) > 1e-9 ? 1.0 / std::fabs(d.z) : inf;
	double tmx = std::fabs(d.x) > 1e-9 ? ((sx > 0 ? (ix + 1 - p.x) : (p.x - ix)) * tdx) : inf;
	double tmy = std::fabs(d.y) > 1e-9 ? ((sy > 0 ? (iy + 1 - p.y) : (p.y - iy)) * tdy) : inf;
	double tmz = std::fabs(d.z) > 1e-9 ? ((sz > 0 ? (iz + 1 - p.z) : (p.z - iz)) * tdz) : inf;
	int axis = -1;
	double tcur = 0.0;
	for (int it = 0; it < 200000; it++) {
		const uint8_t v = acc.vget(ix, iy, iz);
		if (v != 0 && v != 255 && (t.solid[v] || (hit_water && t.water[v]))) {
			r["hit"] = true;
			r["voxel"] = Vector3i(ix, iy, iz);
			Vector3i n(0, 0, 0);
			if (axis == 0) {
				n.x = -sx;
			} else if (axis == 1) {
				n.y = -sy;
			} else if (axis == 2) {
				n.z = -sz;
			}
			r["normal"] = n;
			r["value"] = (int)v;
			r["t"] = tcur;
			r["point"] = p + d * (float)tcur;
			return r;
		}
		if (v == 255 && it > 0) {
			return r;
		}
		if (tmx < tmy && tmx < tmz) {
			tcur = tmx;
			tmx += tdx;
			ix += sx;
			axis = 0;
		} else if (tmy < tmz) {
			tcur = tmy;
			tmy += tdy;
			iy += sy;
			axis = 1;
		} else {
			tcur = tmz;
			tmz += tdz;
			iz += sz;
			axis = 2;
		}
		if (tcur > max_t) {
			break;
		}
	}
	return r;
}

Dictionary VoxelVolume::raycast(Vector3 from, Vector3 dir, float max_dist, bool hit_water) {
	VolumeAccess acc(this);
	Dictionary r = dda(acc, t, (from - origin) / vs, dir, max_dist / vs, hit_water);
	if ((bool)r["hit"]) {
		r["point"] = origin + (Vector3)r["point"] * vs;
		r["distance"] = (float)(double)r["t"] * vs;
	}
	return r;
}

static Dictionary removed_to_dict(const std::vector<int32_t> &removed) {
	Dictionary d;
	PackedInt32Array arr;
	arr.resize((int64_t)removed.size());
	if (!removed.empty()) {
		memcpy(arr.ptrw(), removed.data(), removed.size() * sizeof(int32_t));
	}
	d["removed"] = arr;
	if (!removed.empty()) {
		Vector3i lo(INT32_MAX, INT32_MAX, INT32_MAX), hi(INT32_MIN, INT32_MIN, INT32_MIN);
		for (size_t i = 0; i < removed.size(); i += 4) {
			lo.x = std::min(lo.x, removed[i]);
			lo.y = std::min(lo.y, removed[i + 1]);
			lo.z = std::min(lo.z, removed[i + 2]);
			hi.x = std::max(hi.x, removed[i]);
			hi.y = std::max(hi.y, removed[i + 1]);
			hi.z = std::max(hi.z, removed[i + 2]);
		}
		d["lo"] = lo;
		d["hi"] = hi;
	}
	return d;
}

Dictionary VoxelVolume::carve_cluster(Vector3i at, Vector3i normal, int count, int max_hard, int seed, float jitter, Vector3i lo, Vector3i hi) {
	VolumeAccess acc(this);
	std::vector<int32_t> removed;
	carve_cluster_impl(acc, t, at, normal, count, max_hard, seed, jitter, lo, hi, removed);
	return removed_to_dict(removed);
}

Dictionary VoxelVolume::apply_object(Ref<VoxelObject> obj, Vector3i at, int mode, int pattern, bool natural) {
	Dictionary r;
	if (obj.is_null()) {
		return r;
	}
	const VxBuf &g = obj->g;
	std::vector<int32_t> changes;
	PackedInt32Array counts;
	counts.resize(256);
	int32_t *cw = counts.ptrw();
	memset(cw, 0, 256 * sizeof(int32_t));
	Vector3i lo(INT32_MAX, INT32_MAX, INT32_MAX), hi(INT32_MIN, INT32_MIN, INT32_MIN);
	for (int i = 0; i < g.X; i++) {
		for (int j = 0; j < g.Y; j++) {
			for (int k = 0; k < g.Z; k++) {
				const uint8_t ov = g.at(i, j, k);
				if (!ov) {
					continue;
				}
				const int x = at.x + i, y = at.y + j, z = at.z + k;
				const uint8_t cur = get(x, y, z);
				if (cur == 255) {
					continue;
				}
				uint8_t nv = cur;
				if (mode == 0) { // add into air / water
					if (cur != 0 && !t.water[cur]) {
						continue;
					}
					const int mat = ov >> 2;
					if (pattern < 0) {
						nv = ov; // exact copy (blueprints)
					} else {
						nv = (uint8_t)((mat << 2) | (natural ? pattern_variant(0, mat, x, y, z) : pattern_variant(pattern, mat, x, y, z)));
					}
				} else if (mode == 1) { // subtract
					if (!t.solid[cur] || t.hard[cur] == 255) {
						continue;
					}
					nv = 0;
				} else { // paint
					if (!t.solid[cur]) {
						continue;
					}
					const int mat = ov >> 2;
					nv = (uint8_t)((mat << 2) | pattern_variant(pattern, mat, x, y, z));
					if (nv == cur) {
						continue;
					}
				}
				if (!set(x, y, z, nv)) {
					continue;
				}
				changes.push_back(x);
				changes.push_back(y);
				changes.push_back(z);
				changes.push_back(cur);
				changes.push_back(nv);
				cw[mode == 1 ? cur : nv] += 1;
				lo.x = std::min(lo.x, x);
				lo.y = std::min(lo.y, y);
				lo.z = std::min(lo.z, z);
				hi.x = std::max(hi.x, x);
				hi.y = std::max(hi.y, y);
				hi.z = std::max(hi.z, z);
			}
		}
	}
	PackedInt32Array ch;
	ch.resize((int64_t)changes.size());
	if (!changes.empty()) {
		memcpy(ch.ptrw(), changes.data(), changes.size() * sizeof(int32_t));
	}
	r["changes"] = ch;
	r["counts"] = counts;
	if (!changes.empty()) {
		r["lo"] = lo;
		r["hi"] = hi;
	}
	return r;
}

PackedInt32Array VoxelVolume::set_voxels(PackedInt32Array list) {
	// list: x, y, z, value ... ; returns the previous values in the same layout
	PackedInt32Array prev;
	prev.resize(list.size());
	int32_t *pw = prev.ptrw();
	const int32_t *l = list.ptr();
	for (int64_t i = 0; i + 3 < list.size(); i += 4) {
		pw[i] = l[i];
		pw[i + 1] = l[i + 1];
		pw[i + 2] = l[i + 2];
		pw[i + 3] = get(l[i], l[i + 1], l[i + 2]);
		set(l[i], l[i + 1], l[i + 2], (uint8_t)l[i + 3]);
	}
	return prev;
}

bool VoxelVolume::touches_solid(Ref<VoxelObject> obj, Vector3i at) {
	if (obj.is_null()) {
		return false;
	}
	const VxBuf &g = obj->g;
	for (int i = 0; i < g.X; i++) {
		for (int j = 0; j < g.Y; j++) {
			for (int k = 0; k < g.Z; k++) {
				if (!g.at(i, j, k)) {
					continue;
				}
				for (int d = 0; d < 6; d++) {
					const uint8_t v = get(at.x + i + DIRS[d][0], at.y + j + DIRS[d][1], at.z + k + DIRS[d][2]);
					if (v && v != 255 && t.solid[v]) {
						return true;
					}
				}
			}
		}
	}
	return false;
}

int VoxelVolume::count_overlap(Ref<VoxelObject> obj, Vector3i at) {
	if (obj.is_null()) {
		return 0;
	}
	int n = 0;
	const VxBuf &g = obj->g;
	for (int i = 0; i < g.X; i++) {
		for (int j = 0; j < g.Y; j++) {
			for (int k = 0; k < g.Z; k++) {
				if (!g.at(i, j, k)) {
					continue;
				}
				const uint8_t v = get(at.x + i, at.y + j, at.z + k);
				if (v && t.solid[v]) {
					n++;
				}
			}
		}
	}
	return n;
}

static Ref<VoxelObject> island_object(const Island &isl, const VxTables &t, float vs, Vector3i &origin_out) {
	Vector3i lo(INT32_MAX, INT32_MAX, INT32_MAX), hi(INT32_MIN, INT32_MIN, INT32_MIN);
	for (size_t i = 0; i < isl.vox.size(); i += 4) {
		lo.x = std::min(lo.x, isl.vox[i]);
		lo.y = std::min(lo.y, isl.vox[i + 1]);
		lo.z = std::min(lo.z, isl.vox[i + 2]);
		hi.x = std::max(hi.x, isl.vox[i]);
		hi.y = std::max(hi.y, isl.vox[i + 1]);
		hi.z = std::max(hi.z, isl.vox[i + 2]);
	}
	Ref<VoxelObject> o;
	o.instantiate();
	o->copy_tables(t);
	o->vs = vs;
	o->g.alloc(hi.x - lo.x + 1, hi.y - lo.y + 1, hi.z - lo.z + 1, 0);
	for (size_t i = 0; i < isl.vox.size(); i += 4) {
		o->g.ref(isl.vox[i] - lo.x, isl.vox[i + 1] - lo.y, isl.vox[i + 2] - lo.z) = (uint8_t)isl.vox[i + 3];
	}
	origin_out = lo;
	return o;
}

Array VoxelVolume::find_islands(Vector3i lo, Vector3i hi, int limit) {
	VolumeAccess acc(this);
	std::vector<Island> isl;
	find_islands_impl(acc, t, lo, hi, limit, isl);
	Array out;
	for (const Island &is : isl) {
		for (size_t i = 0; i < is.vox.size(); i += 4) {
			set(is.vox[i], is.vox[i + 1], is.vox[i + 2], 0);
		}
		Vector3i o;
		Ref<VoxelObject> obj = island_object(is, t, vs, o);
		Dictionary d;
		d["origin"] = o;
		d["object"] = obj;
		d["count"] = (int)(is.vox.size() / 4);
		out.push_back(d);
	}
	return out;
}

int VoxelVolume::column_top(int x, int z) {
	const int cx = floordiv(x, cs), cz = floordiv(z, cs);
	Chunk *c = find(cx, cz);
	if (!c) {
		return INT32_MIN;
	}
	const int lx = x - cx * cs, lz = z - cz * cs;
	for (int ly = c->cy - 1; ly >= 0; ly--) {
		const uint8_t v = c->d[((size_t)lx * c->cy + ly) * cs + lz];
		if (v && t.solid[v]) {
			return c->y_lo + ly;
		}
	}
	return c->y_lo - 1;
}

// replays a change list (x, y, z, old, new per entry): column 3 restores (undo), column 4 re-applies (redo)
Dictionary VoxelVolume::apply_changes(PackedInt32Array list, int column) {
	Dictionary r;
	const int64_t n = list.size() / 5;
	if (n == 0 || column < 3 || column > 4) {
		return r;
	}
	const int32_t *p = list.ptr();
	Vector3i lo(INT32_MAX, INT32_MAX, INT32_MAX), hi(INT32_MIN, INT32_MIN, INT32_MIN);
	for (int64_t i = 0; i < n; i++) {
		const int32_t *e = p + i * 5;
		set(e[0], e[1], e[2], (uint8_t)e[column]);
		lo.x = std::min(lo.x, e[0]);
		lo.y = std::min(lo.y, e[1]);
		lo.z = std::min(lo.z, e[2]);
		hi.x = std::max(hi.x, e[0]);
		hi.y = std::max(hi.y, e[1]);
		hi.z = std::max(hi.z, e[2]);
	}
	r["lo"] = lo;
	r["hi"] = hi;
	return r;
}

// voxels whose value is set in `mask` inside a sphere (x, y, z, value per hit), nearest first is not guaranteed
PackedInt32Array VoxelVolume::find_values(Vector3i center, int radius, PackedByteArray mask, int max_count) {
	PackedInt32Array out;
	if (mask.size() < 256 || radius <= 0) {
		return out;
	}
	const uint8_t *m = mask.ptr();
	const int r2 = radius * radius;
	int n = 0;
	for (int dx = -radius; dx <= radius && n < max_count; dx++) {
		for (int dz = -radius; dz <= radius && n < max_count; dz++) {
			if (dx * dx + dz * dz > r2) {
				continue;
			}
			for (int dy = -radius; dy <= radius; dy++) {
				if (dx * dx + dy * dy + dz * dz > r2) {
					continue;
				}
				const uint8_t v = get(center.x + dx, center.y + dy, center.z + dz);
				if (v != 255 && m[v]) {
					out.push_back(center.x + dx);
					out.push_back(center.y + dy);
					out.push_back(center.z + dz);
					out.push_back(v);
					if (++n >= max_count) {
						break;
					}
				}
			}
		}
	}
	return out;
}

// extends the bottom row of a shape down to the ground (columns that find no ground within max_depth stay as they are)
Dictionary VoxelVolume::foundation(Ref<VoxelObject> obj, Vector3i at, int max_depth) {
	Dictionary r;
	if (obj.is_null()) {
		return r;
	}
	const VxBuf &g = obj->g;
	std::vector<int> depth((size_t)g.X * g.Z, 0);
	int ext = 0;
	for (int i = 0; i < g.X; i++) {
		for (int k = 0; k < g.Z; k++) {
			if (!g.at(i, 0, k)) {
				continue;
			}
			int d = 0;
			bool found = false;
			for (; d < max_depth; d++) {
				const uint8_t v = get(at.x + i, at.y - 1 - d, at.z + k);
				if (v == 255 || (v && t.solid[v])) {
					found = true;
					break;
				}
			}
			if (found) {
				depth[(size_t)i * g.Z + k] = d;
				ext = std::max(ext, d);
			}
		}
	}
	Ref<VoxelObject> o;
	o.instantiate();
	o->copy_tables(obj->t);
	o->vs = obj->vs;
	o->g.alloc(g.X, g.Y + ext, g.Z, 0);
	for (int i = 0; i < g.X; i++) {
		for (int k = 0; k < g.Z; k++) {
			for (int j = 0; j < g.Y; j++) {
				o->g.ref(i, j + ext, k) = g.at(i, j, k);
			}
			const int d = depth[(size_t)i * g.Z + k];
			const uint8_t b = g.at(i, 0, k);
			for (int j = ext - d; j < ext; j++) {
				o->g.ref(i, j, k) = b;
			}
		}
	}
	r["object"] = o;
	r["shift"] = ext;
	return r;
}

Ref<VoxelObject> VoxelVolume::copy_region(Vector3i lo, Vector3i size) {
	Ref<VoxelObject> o;
	o.instantiate();
	o->copy_tables(t);
	o->vs = vs;
	extract(lo.x, lo.y, lo.z, size.x, size.y, size.z, o->g);
	for (uint8_t &v : o->g.d) {
		if (v == 255 || t.water[v]) {
			v = 0;
		}
	}
	return o;
}

void VoxelVolume::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "origin", "voxel_size", "chunk_size"), &VoxelVolume::setup);
	ClassDB::bind_method(D_METHOD("set_tables", "solid", "water", "hard", "deep"), &VoxelVolume::set_tables);
	ClassDB::bind_method(D_METHOD("load_chunk", "cx", "cz", "y_lo", "cy", "data"), &VoxelVolume::load_chunk);
	ClassDB::bind_method(D_METHOD("has_chunk", "cx", "cz"), &VoxelVolume::has_chunk);
	ClassDB::bind_method(D_METHOD("unload_chunk", "cx", "cz"), &VoxelVolume::unload_chunk);
	ClassDB::bind_method(D_METHOD("get_chunk_data", "cx", "cz"), &VoxelVolume::get_chunk_data);
	ClassDB::bind_method(D_METHOD("get_chunk_range", "cx", "cz"), &VoxelVolume::get_chunk_range);
	ClassDB::bind_method(D_METHOD("get_voxel", "p"), &VoxelVolume::get_voxel);
	ClassDB::bind_method(D_METHOD("set_voxel", "p", "v"), &VoxelVolume::set_voxel);
	ClassDB::bind_method(D_METHOD("mesh_region", "lo", "size", "lod", "water", "ao", "offset"), &VoxelVolume::mesh_region);
	ClassDB::bind_method(D_METHOD("collision_region", "lo", "size", "offset"), &VoxelVolume::collision_region);
	ClassDB::bind_method(D_METHOD("raycast", "from", "dir", "max_dist", "hit_water"), &VoxelVolume::raycast);
	ClassDB::bind_method(D_METHOD("carve_cluster", "at", "normal", "count", "max_hard", "seed", "jitter", "lo", "hi"), &VoxelVolume::carve_cluster);
	ClassDB::bind_method(D_METHOD("apply_object", "obj", "at", "mode", "pattern", "natural"), &VoxelVolume::apply_object);
	ClassDB::bind_method(D_METHOD("set_voxels", "list"), &VoxelVolume::set_voxels);
	ClassDB::bind_method(D_METHOD("touches_solid", "obj", "at"), &VoxelVolume::touches_solid);
	ClassDB::bind_method(D_METHOD("count_overlap", "obj", "at"), &VoxelVolume::count_overlap);
	ClassDB::bind_method(D_METHOD("find_islands", "lo", "hi", "limit"), &VoxelVolume::find_islands);
	ClassDB::bind_method(D_METHOD("column_top", "x", "z"), &VoxelVolume::column_top);
	ClassDB::bind_method(D_METHOD("copy_region", "lo", "size"), &VoxelVolume::copy_region);
	ClassDB::bind_method(D_METHOD("foundation", "obj", "at", "max_depth"), &VoxelVolume::foundation);
	ClassDB::bind_method(D_METHOD("apply_changes", "list", "column"), &VoxelVolume::apply_changes);
	ClassDB::bind_method(D_METHOD("find_values", "center", "radius", "mask", "max_count"), &VoxelVolume::find_values);
}

// ------------------------------------------------------------------ VoxelObject
class ObjectAccess : public VxAccess {
public:
	VoxelObject *o;
	int anchor_mode = 0;
	explicit ObjectAccess(VoxelObject *p) :
			o(p) {}
	uint8_t vget(int x, int y, int z) override {
		const VxBuf &g = o->g;
		if (x < 0 || y < 0 || z < 0 || x >= g.X || y >= g.Y || z >= g.Z) {
			return 0;
		}
		return g.at(x, y, z);
	}
	void vset(int x, int y, int z, uint8_t v) override {
		VxBuf &g = o->g;
		if (x < 0 || y < 0 || z < 0 || x >= g.X || y >= g.Y || z >= g.Z) {
			return;
		}
		g.ref(x, y, z) = v;
	}
	bool anchored(int x, int y, int z, uint8_t v) override { return anchor_mode == 1 && y == 0; }
};

void VoxelObject::set_tables(PackedByteArray solid, PackedByteArray water, PackedByteArray hard, int deep) {
	tables_from(t, solid, water, hard, deep);
}

void VoxelObject::create(Vector3i size) {
	g.alloc(std::max(1, size.x), std::max(1, size.y), std::max(1, size.z), 0);
}

void VoxelObject::set_data(Vector3i size, PackedByteArray data) {
	create(size);
	const size_t n = std::min((size_t)data.size(), g.d.size());
	memcpy(g.d.data(), data.ptr(), n);
}

PackedByteArray VoxelObject::get_data() {
	PackedByteArray out;
	out.resize((int64_t)g.d.size());
	memcpy(out.ptrw(), g.d.data(), g.d.size());
	return out;
}

Vector3i VoxelObject::get_size() {
	return Vector3i(g.X, g.Y, g.Z);
}

int VoxelObject::get_voxel(Vector3i p) {
	if (p.x < 0 || p.y < 0 || p.z < 0 || p.x >= g.X || p.y >= g.Y || p.z >= g.Z) {
		return 0;
	}
	return g.at(p.x, p.y, p.z);
}

void VoxelObject::set_voxel(Vector3i p, int v) {
	if (p.x < 0 || p.y < 0 || p.z < 0 || p.x >= g.X || p.y >= g.Y || p.z >= g.Z) {
		return;
	}
	g.ref(p.x, p.y, p.z) = (uint8_t)v;
}

int VoxelObject::solid_count() {
	int n = 0;
	for (uint8_t v : g.d) {
		n += (v && t.solid[v]) ? 1 : 0;
	}
	return n;
}

PackedInt32Array VoxelObject::value_counts() {
	PackedInt32Array c;
	c.resize(256);
	int32_t *w = c.ptrw();
	memset(w, 0, 256 * sizeof(int32_t));
	for (uint8_t v : g.d) {
		if (v) {
			w[v]++;
		}
	}
	return c;
}

static void object_extract(const VxBuf &g, int x0, int y0, int z0, int X, int Y, int Z, VxBuf &b) {
	b.alloc(X, Y, Z, 0);
	for (int i = 0; i < X; i++) {
		const int x = x0 + i;
		if (x < 0 || x >= g.X) {
			continue;
		}
		for (int j = 0; j < Y; j++) {
			const int y = y0 + j;
			if (y < 0 || y >= g.Y) {
				continue;
			}
			for (int k = 0; k < Z; k++) {
				const int z = z0 + k;
				if (z < 0 || z >= g.Z) {
					continue;
				}
				b.ref(i, j, k) = g.at(x, y, z);
			}
		}
	}
}

Dictionary VoxelObject::mesh(int lod, bool ao, Vector3 offset) {
	const int f = 1 << lod;
	const int X = ((g.X + f - 1) / f) * f, Y = ((g.Y + f - 1) / f) * f, Z = ((g.Z + f - 1) / f) * f;
	return mesh_region(Vector3i(0, 0, 0), Vector3i(X, Y, Z), lod, ao, offset);
}

Dictionary VoxelObject::mesh_region(Vector3i lo, Vector3i size, int lod, bool ao, Vector3 offset) {
	const int f = 1 << lod;
	VxBuf b;
	object_extract(g, lo.x - f, lo.y - f, lo.z - f, size.x + 2 * f, size.y + 2 * f, size.z + 2 * f, b);
	return mesh_buffer_lod(b, t, lod, false, ao, vs, offset);
}

PackedFloat32Array VoxelObject::boxes(int cell, int max_boxes) {
	PackedFloat32Array out;
	for (int attempt = 0; attempt < 6; attempt++, cell *= 2) {
		const int CX = (g.X + cell - 1) / cell, CY = (g.Y + cell - 1) / cell, CZ = (g.Z + cell - 1) / cell;
		std::vector<uint8_t> occ((size_t)CX * CY * CZ, 0);
		for (int i = 0; i < CX; i++) {
			for (int j = 0; j < CY; j++) {
				for (int k = 0; k < CZ; k++) {
					int n = 0, tot = 0;
					for (int a = i * cell; a < std::min(g.X, (i + 1) * cell); a++) {
						for (int b = j * cell; b < std::min(g.Y, (j + 1) * cell); b++) {
							for (int c = k * cell; c < std::min(g.Z, (k + 1) * cell); c++) {
								tot++;
								const uint8_t v = g.at(a, b, c);
								n += (v && t.solid[v]) ? 1 : 0;
							}
						}
					}
					occ[((size_t)i * CY + j) * CZ + k] = (tot > 0 && n * 10 >= tot * 3) ? 1 : 0;
				}
			}
		}
		auto O = [&](int i, int j, int k) -> uint8_t & { return occ[((size_t)i * CY + j) * CZ + k]; };
		std::vector<float> bx;
		int count = 0;
		for (int i = 0; i < CX; i++) {
			for (int j = 0; j < CY; j++) {
				for (int k = 0; k < CZ; k++) {
					if (O(i, j, k) != 1) {
						continue;
					}
					int w = 1, d = 1, h = 1;
					while (i + w < CX && O(i + w, j, k) == 1) {
						w++;
					}
					bool ok = true;
					while (ok && k + d < CZ) {
						for (int a = 0; a < w; a++) {
							if (O(i + a, j, k + d) != 1) {
								ok = false;
								break;
							}
						}
						if (ok) {
							d++;
						}
					}
					ok = true;
					while (ok && j + h < CY) {
						for (int a = 0; a < w && ok; a++) {
							for (int c = 0; c < d; c++) {
								if (O(i + a, j + h, k + c) != 1) {
									ok = false;
									break;
								}
							}
						}
						if (ok) {
							h++;
						}
					}
					for (int a = 0; a < w; a++) {
						for (int b = 0; b < h; b++) {
							for (int c = 0; c < d; c++) {
								O(i + a, j + b, k + c) = 2;
							}
						}
					}
					const float x0 = (float)(i * cell), y0 = (float)(j * cell), z0 = (float)(k * cell);
					const float x1 = (float)std::min(g.X, (i + w) * cell), y1 = (float)std::min(g.Y, (j + h) * cell),
								z1 = (float)std::min(g.Z, (k + d) * cell);
					bx.push_back((x0 + x1) * 0.5f);
					bx.push_back((y0 + y1) * 0.5f);
					bx.push_back((z0 + z1) * 0.5f);
					bx.push_back(x1 - x0);
					bx.push_back(y1 - y0);
					bx.push_back(z1 - z0);
					count++;
				}
			}
		}
		if (count <= max_boxes || attempt == 5) {
			out.resize((int64_t)bx.size());
			if (!bx.empty()) {
				memcpy(out.ptrw(), bx.data(), bx.size() * sizeof(float));
			}
			return out;
		}
	}
	return out;
}

Dictionary VoxelObject::raycast(Vector3 from, Vector3 dir, float max_dist) {
	ObjectAccess acc(this);
	return dda(acc, t, from, dir, max_dist, false);
}

Dictionary VoxelObject::carve_cluster(Vector3i at, Vector3i normal, int count, int max_hard, int seed, float jitter, Vector3i lo, Vector3i hi) {
	ObjectAccess acc(this);
	std::vector<int32_t> removed;
	carve_cluster_impl(acc, t, at, normal, count, max_hard, seed, jitter, lo, hi, removed);
	return removed_to_dict(removed);
}

PackedInt32Array VoxelObject::remove_box(Vector3i lo, Vector3i hi, int max_hard) {
	std::vector<int32_t> removed;
	for (int x = std::max(0, lo.x); x <= std::min(g.X - 1, hi.x); x++) {
		for (int y = std::max(0, lo.y); y <= std::min(g.Y - 1, hi.y); y++) {
			for (int z = std::max(0, lo.z); z <= std::min(g.Z - 1, hi.z); z++) {
				const uint8_t v = g.at(x, y, z);
				if (v && t.solid[v] && t.hard[v] <= max_hard) {
					g.ref(x, y, z) = 0;
					removed.push_back(x);
					removed.push_back(y);
					removed.push_back(z);
					removed.push_back(v);
				}
			}
		}
	}
	PackedInt32Array out;
	out.resize((int64_t)removed.size());
	if (!removed.empty()) {
		memcpy(out.ptrw(), removed.data(), removed.size() * sizeof(int32_t));
	}
	return out;
}

int VoxelObject::count_box(Vector3i lo, Vector3i hi) {
	int n = 0;
	for (int x = std::max(0, lo.x); x <= std::min(g.X - 1, hi.x); x++) {
		for (int y = std::max(0, lo.y); y <= std::min(g.Y - 1, hi.y); y++) {
			for (int z = std::max(0, lo.z); z <= std::min(g.Z - 1, hi.z); z++) {
				const uint8_t v = g.at(x, y, z);
				n += (v && t.solid[v]) ? 1 : 0;
			}
		}
	}
	return n;
}

Array VoxelObject::split(int anchor_mode) {
	// components that are not anchored are removed from this object and returned as new objects
	ObjectAccess acc(this);
	acc.anchor_mode = anchor_mode;
	std::vector<Island> isl;
	find_islands_impl(acc, t, Vector3i(0, 0, 0), Vector3i(g.X - 1, g.Y - 1, g.Z - 1), 1 << 30, isl);
	Array out;
	if (anchor_mode == 0 && isl.size() <= 1) {
		return out;
	}
	for (const Island &is : isl) {
		for (size_t i = 0; i < is.vox.size(); i += 4) {
			g.ref(is.vox[i], is.vox[i + 1], is.vox[i + 2]) = 0;
		}
		Vector3i o;
		Ref<VoxelObject> obj = island_object(is, t, vs, o);
		Dictionary d;
		d["origin"] = o;
		d["object"] = obj;
		d["count"] = (int)(is.vox.size() / 4);
		out.push_back(d);
	}
	return out;
}

Vector3i VoxelObject::trim() {
	Vector3i lo(INT32_MAX, INT32_MAX, INT32_MAX), hi(-1, -1, -1);
	for (int x = 0; x < g.X; x++) {
		for (int y = 0; y < g.Y; y++) {
			for (int z = 0; z < g.Z; z++) {
				if (g.at(x, y, z)) {
					lo.x = std::min(lo.x, x);
					lo.y = std::min(lo.y, y);
					lo.z = std::min(lo.z, z);
					hi.x = std::max(hi.x, x);
					hi.y = std::max(hi.y, y);
					hi.z = std::max(hi.z, z);
				}
			}
		}
	}
	if (hi.x < 0) {
		g.alloc(1, 1, 1, 0);
		return Vector3i(0, 0, 0);
	}
	VxBuf nb;
	object_extract(g, lo.x, lo.y, lo.z, hi.x - lo.x + 1, hi.y - lo.y + 1, hi.z - lo.z + 1, nb);
	g = std::move(nb);
	return lo;
}

void VoxelObject::fill_shape(int kind, Vector3i size, Dictionary params, int value) {
	const int SX = std::max(1, size.x), SY = std::max(1, size.y), SZ = std::max(1, size.z);
	g.alloc(SX, SY, SZ, 0);
	const bool hollow = params.get("hollow", false);
	const int th = std::max(1, (int)params.get("thick", 1));
	const bool open_top = params.get("open_top", false);
	const bool open_bottom = params.get("open_bottom", false);
	const bool half = params.get("half", false);
	const int step_h = std::max(1, (int)params.get("step", 2));
	const bool fill_under = params.get("fill_under", true);
	const int crenel = (int)params.get("crenel", 0);
	const uint8_t val = (uint8_t)value;
	const float cx = SX * 0.5f, cz = SZ * 0.5f;
	for (int i = 0; i < SX; i++) {
		for (int j = 0; j < SY; j++) {
			for (int k = 0; k < SZ; k++) {
				const float x = i + 0.5f, y = j + 0.5f, z = k + 0.5f;
				bool in = false;
				switch (kind) {
					case 0: { // box / wall / floor
						in = true;
						if (hollow) {
							in = i < th || i >= SX - th || k < th || k >= SZ - th || (!open_bottom && j < th) || (!open_top && j >= SY - th);
						}
					} break;
					case 1:
					case 7: { // sphere / ellipsoid (7 = brush, always solid); half = dome
						const float rx = SX * 0.5f, rz = SZ * 0.5f;
						const float ry = half ? (float)SY : SY * 0.5f;
						const float cy = half ? 0.0f : SY * 0.5f;
						const float q = ((x - cx) / rx) * ((x - cx) / rx) + ((y - cy) / ry) * ((y - cy) / ry) + ((z - cz) / rz) * ((z - cz) / rz);
						in = q <= 1.0f;
						if (in && hollow && kind == 1) {
							const float ix = std::max(0.5f, rx - th), iy = std::max(0.5f, ry - th), iz = std::max(0.5f, rz - th);
							const float qi = ((x - cx) / ix) * ((x - cx) / ix) + ((y - cy) / iy) * ((y - cy) / iy) + ((z - cz) / iz) * ((z - cz) / iz);
							in = qi > 1.0f || (!open_bottom && half && j < th);
						}
					} break;
					case 2: { // cylinder (tower when hollow)
						const float rx = SX * 0.5f, rz = SZ * 0.5f;
						const float q = ((x - cx) / rx) * ((x - cx) / rx) + ((z - cz) / rz) * ((z - cz) / rz);
						in = q <= 1.0f;
						if (in && hollow) {
							const float ix = std::max(0.5f, rx - th), iz = std::max(0.5f, rz - th);
							const float qi = ((x - cx) / ix) * ((x - cx) / ix) + ((z - cz) / iz) * ((z - cz) / iz);
							in = qi > 1.0f || (!open_bottom && j < th) || (!open_top && j >= SY - th);
						}
					} break;
					case 3: { // arch: block with a round-topped opening through z
						const float ow = std::max(1.0f, (float)SX - 2.0f * th);
						const float r = ow * 0.5f;
						const int top = std::max(1, (int)params.get("top", th));
						const float hs = std::max(0.0f, (float)SY - top - r);
						const float dx = x - cx;
						bool open = false;
						if (std::fabs(dx) < r) {
							if (y < hs) {
								open = true;
							} else {
								open = dx * dx + (y - hs) * (y - hs) < r * r;
							}
						}
						in = !open;
					} break;
					case 4: { // stairs rising along +z
						const int nsteps = std::max(1, (SY + step_h - 1) / step_h);
						const float depth = (float)SZ / nsteps;
						const int si = std::min(nsteps - 1, (int)(z / depth));
						const int top = std::min(SY, (si + 1) * step_h);
						in = j < top;
						if (in && !fill_under) {
							in = j >= top - 2 * step_h; // floating flight of steps
						}
					} break;
					case 5: { // gable roof, ridge along x (half = shed roof rising along +z)
						float h;
						if (half) {
							h = z / SZ * SY;
						} else {
							h = std::min(z, SZ - z) / (SZ * 0.5f) * SY;
						}
						in = y <= h + 0.25f;
						if (in && hollow) {
							in = y > h - th * 1.4f;
						}
					} break;
					case 6: { // pillar with base and capital
						const bool cap = j < th || j >= SY - th;
						if (cap) {
							in = true;
						} else {
							const float rx = SX * 0.36f, rz = SZ * 0.36f;
							in = ((x - cx) / rx) * ((x - cx) / rx) + ((z - cz) / rz) * ((z - cz) / rz) <= 1.0f;
						}
					} break;
					case 8: { // ramp / wedge
						in = y <= z / SZ * SY + 0.25f;
					} break;
					default:
						in = true;
				}
				// battlements: the top rows get alternating gaps (walls along x / z, towers around the ring)
				if (in && crenel > 0 && j >= SY - crenel && SY > crenel * 2) {
					if (kind == 2) {
						const float circ = 3.14159265f * (SX + SZ) * 0.5f;
						int nseg = std::max(4, (int)std::lround(circ / (crenel * 2.0f)) * 2);
						const float a = std::atan2(z - cz, x - cx) + 3.14159265f;
						const int seg = std::min(nseg - 1, (int)(a / 6.2831853f * nseg));
						in = (seg & 1) == 0;
					} else {
						in = ((i / crenel + k / crenel) & 1) == 0;
					}
				}
				if (in) {
					g.ref(i, j, k) = val;
				}
			}
		}
	}
}

void VoxelObject::rotate_y(int quarter_turns) {
	int q = ((quarter_turns % 4) + 4) % 4;
	for (int n = 0; n < q; n++) {
		VxBuf nb;
		nb.alloc(g.Z, g.Y, g.X, 0);
		for (int x = 0; x < g.X; x++) {
			for (int y = 0; y < g.Y; y++) {
				for (int z = 0; z < g.Z; z++) {
					// (x, z) -> (z', x') = (g.Z-1-z, x)
					nb.ref(g.Z - 1 - z, y, x) = g.at(x, y, z);
				}
			}
		}
		g = std::move(nb);
	}
}

int VoxelObject::filter_values(PackedByteArray keep) {
	if (keep.size() < 256) {
		return 0;
	}
	const uint8_t *kp = keep.ptr();
	int n = 0;
	for (uint8_t &v : g.d) {
		if (v && !kp[v]) {
			v = 0;
			n++;
		}
	}
	return n;
}

Ref<VoxelObject> VoxelObject::duplicate_object() {
	Ref<VoxelObject> o;
	o.instantiate();
	o->t = t;
	o->vs = vs;
	o->g = g;
	return o;
}

// recolour every solid voxel (keeps the shape): material of `value`, variant from the pattern at local coords
void VoxelObject::paint_all(int value, int pattern, Vector3i origin) {
	const int mat = value >> 2;
	for (int x = 0; x < g.X; x++) {
		for (int y = 0; y < g.Y; y++) {
			for (int z = 0; z < g.Z; z++) {
				uint8_t &v = g.ref(x, y, z);
				if (v) {
					v = pattern < 0 ? (uint8_t)value : (uint8_t)((mat << 2) | pattern_variant(pattern, mat, origin.x + x, origin.y + y, origin.z + z));
				}
			}
		}
	}
}

// copies another object into this one: mode 0 = overwrite with solid source voxels, 1 = only into empty cells,
// 2 = clear wherever the source is solid (cut-outs)
void VoxelObject::blit(Ref<VoxelObject> src, Vector3i at, int mode) {
	if (src.is_null()) {
		return;
	}
	const VxBuf &s = src->g;
	for (int x = 0; x < s.X; x++) {
		const int dx = at.x + x;
		if (dx < 0 || dx >= g.X) {
			continue;
		}
		for (int y = 0; y < s.Y; y++) {
			const int dy = at.y + y;
			if (dy < 0 || dy >= g.Y) {
				continue;
			}
			for (int z = 0; z < s.Z; z++) {
				const int dz = at.z + z;
				if (dz < 0 || dz >= g.Z) {
					continue;
				}
				const uint8_t v = s.at(x, y, z);
				if (!v) {
					continue;
				}
				uint8_t &d = g.ref(dx, dy, dz);
				if (mode == 2) {
					d = 0;
				} else if (mode == 0 || !d) {
					d = v;
				}
			}
		}
	}
}

void VoxelObject::mirror_x() {
	for (int x = 0; x < g.X / 2; x++) {
		for (int y = 0; y < g.Y; y++) {
			for (int z = 0; z < g.Z; z++) {
				std::swap(g.ref(x, y, z), g.ref(g.X - 1 - x, y, z));
			}
		}
	}
}

Vector3 VoxelObject::center_of_mass() {
	double sx = 0, sy = 0, sz = 0;
	int n = 0;
	for (int x = 0; x < g.X; x++) {
		for (int y = 0; y < g.Y; y++) {
			for (int z = 0; z < g.Z; z++) {
				const uint8_t v = g.at(x, y, z);
				if (v && t.solid[v]) {
					sx += x + 0.5;
					sy += y + 0.5;
					sz += z + 0.5;
					n++;
				}
			}
		}
	}
	if (!n) {
		return Vector3(g.X * 0.5f, g.Y * 0.5f, g.Z * 0.5f);
	}
	return Vector3((float)(sx / n), (float)(sy / n), (float)(sz / n));
}

void VoxelObject::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_tables", "solid", "water", "hard", "deep"), &VoxelObject::set_tables);
	ClassDB::bind_method(D_METHOD("set_voxel_size", "vs"), &VoxelObject::set_voxel_size);
	ClassDB::bind_method(D_METHOD("get_voxel_size"), &VoxelObject::get_voxel_size);
	ClassDB::bind_method(D_METHOD("create", "size"), &VoxelObject::create);
	ClassDB::bind_method(D_METHOD("set_data", "size", "data"), &VoxelObject::set_data);
	ClassDB::bind_method(D_METHOD("get_data"), &VoxelObject::get_data);
	ClassDB::bind_method(D_METHOD("get_size"), &VoxelObject::get_size);
	ClassDB::bind_method(D_METHOD("get_voxel", "p"), &VoxelObject::get_voxel);
	ClassDB::bind_method(D_METHOD("set_voxel", "p", "v"), &VoxelObject::set_voxel);
	ClassDB::bind_method(D_METHOD("solid_count"), &VoxelObject::solid_count);
	ClassDB::bind_method(D_METHOD("value_counts"), &VoxelObject::value_counts);
	ClassDB::bind_method(D_METHOD("mesh", "lod", "ao", "offset"), &VoxelObject::mesh);
	ClassDB::bind_method(D_METHOD("mesh_region", "lo", "size", "lod", "ao", "offset"), &VoxelObject::mesh_region);
	ClassDB::bind_method(D_METHOD("boxes", "cell", "max_boxes"), &VoxelObject::boxes);
	ClassDB::bind_method(D_METHOD("raycast", "from", "dir", "max_dist"), &VoxelObject::raycast);
	ClassDB::bind_method(D_METHOD("carve_cluster", "at", "normal", "count", "max_hard", "seed", "jitter", "lo", "hi"), &VoxelObject::carve_cluster);
	ClassDB::bind_method(D_METHOD("remove_box", "lo", "hi", "max_hard"), &VoxelObject::remove_box);
	ClassDB::bind_method(D_METHOD("count_box", "lo", "hi"), &VoxelObject::count_box);
	ClassDB::bind_method(D_METHOD("split", "anchor_mode"), &VoxelObject::split);
	ClassDB::bind_method(D_METHOD("trim"), &VoxelObject::trim);
	ClassDB::bind_method(D_METHOD("fill_shape", "kind", "size", "params", "value"), &VoxelObject::fill_shape);
	ClassDB::bind_method(D_METHOD("rotate_y", "quarter_turns"), &VoxelObject::rotate_y);
	ClassDB::bind_method(D_METHOD("mirror_x"), &VoxelObject::mirror_x);
	ClassDB::bind_method(D_METHOD("center_of_mass"), &VoxelObject::center_of_mass);
	ClassDB::bind_method(D_METHOD("filter_values", "keep"), &VoxelObject::filter_values);
	ClassDB::bind_method(D_METHOD("blit", "src", "at", "mode"), &VoxelObject::blit);
	ClassDB::bind_method(D_METHOD("duplicate_object"), &VoxelObject::duplicate_object);
	ClassDB::bind_method(D_METHOD("paint_all", "value", "pattern", "origin"), &VoxelObject::paint_all);
}
