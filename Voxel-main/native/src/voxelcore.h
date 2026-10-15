// Grünweiten voxel core: chunked terrain volume + small voxel objects.
// Greedy meshing with per-vertex AO in the game's colour-voxel vertex format
// (CUSTOM0 RGBA8 = value, ao 0..3, voxel-size index, 255), collision meshes,
// LOD down-sampling, DDA ray casts, fracture-style carving, shape rasterising for building,
// floating-island detection and box decomposition for rigid bodies.
#pragma once

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/vector2i.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/vector3i.hpp>

#include <cstdint>
#include <unordered_map>
#include <vector>

namespace godot {

struct VxTables {
	uint8_t solid[256];
	uint8_t water[256];
	uint8_t hard[256]; // mining hardness class; 255 = unbreakable
	uint8_t deep = 0; // value below stored data (stone)
	VxTables();
};

struct VxBuf {
	std::vector<uint8_t> d;
	int X = 0, Y = 0, Z = 0;
	void alloc(int x, int y, int z, uint8_t fill = 0) {
		X = x;
		Y = y;
		Z = z;
		d.assign((size_t)x * y * z, fill);
	}
	inline uint8_t at(int x, int y, int z) const { return d[((size_t)x * Y + y) * Z + z]; }
	inline uint8_t &ref(int x, int y, int z) { return d[((size_t)x * Y + y) * Z + z]; }
};

struct VxMesh {
	std::vector<float> pos;
	std::vector<float> nrm;
	std::vector<uint8_t> cus;
	std::vector<int32_t> idx;
	int quads = 0;
};

class VoxelObject;

// Common voxel access for carving / islands (implemented by volume and object).
class VxAccess {
public:
	virtual ~VxAccess() {}
	virtual uint8_t vget(int x, int y, int z) = 0;
	virtual void vset(int x, int y, int z, uint8_t v) = 0;
	virtual bool anchored(int x, int y, int z, uint8_t v) = 0;
};

class VoxelObject : public RefCounted {
	GDCLASS(VoxelObject, RefCounted)

protected:
	static void _bind_methods();

public:
	VxTables t;
	VxBuf g;
	float vs = 0.125f;

	void set_voxel_size(float p_vs) { vs = p_vs; }
	float get_voxel_size() { return vs; }
	PackedInt32Array remove_box(Vector3i lo, Vector3i hi, int max_hard);
	int count_box(Vector3i lo, Vector3i hi);
	void copy_tables(const VxTables &src) { t = src; }
	void set_tables(PackedByteArray solid, PackedByteArray water, PackedByteArray hard, int deep);
	void create(Vector3i size);
	void set_data(Vector3i size, PackedByteArray data);
	PackedByteArray get_data();
	Vector3i get_size();
	int get_voxel(Vector3i p);
	void set_voxel(Vector3i p, int v);
	int solid_count();
	PackedInt32Array value_counts();
	Dictionary mesh(int lod, bool ao, Vector3 offset);
	Dictionary mesh_region(Vector3i lo, Vector3i size, int lod, bool ao, Vector3 offset);
	PackedFloat32Array boxes(int cell, int max_boxes);
	Dictionary raycast(Vector3 from, Vector3 dir, float max_dist);
	Dictionary carve_cluster(Vector3i at, Vector3i normal, int count, int max_hard, int seed, float jitter, Vector3i lo, Vector3i hi);
	Array split(int anchor_mode);
	Vector3i trim();
	void fill_shape(int kind, Vector3i size, Dictionary params, int value);
	void rotate_y(int quarter_turns);
	void mirror_x();
	Vector3 center_of_mass();
	int filter_values(PackedByteArray keep);
	Ref<VoxelObject> duplicate_object();
	void paint_all(int value, int pattern, Vector3i origin);
	void blit(Ref<VoxelObject> src, Vector3i at, int mode);
};


class VoxelVolume : public RefCounted {
	GDCLASS(VoxelVolume, RefCounted)

	struct Chunk {
		int y_lo = 0;
		int cy = 0;
		std::vector<uint8_t> d;
	};

	std::unordered_map<int64_t, Chunk> chunks;
	Chunk *last = nullptr;
	int64_t last_key = INT64_MIN;
	int cs = 128;
	float vs = 0.125f;
	Vector3 origin;

	Chunk *find(int cx, int cz);
	void grow(Chunk &c, int gy);

protected:
	static void _bind_methods();

public:
	VxTables t;

	uint8_t get(int x, int y, int z);
	bool set(int x, int y, int z, uint8_t v);
	void extract(int x0, int y0, int z0, int X, int Y, int Z, VxBuf &b);

	void setup(Vector3 p_origin, float p_vs, int p_chunk);
	void set_tables(PackedByteArray solid, PackedByteArray water, PackedByteArray hard, int deep);
	void load_chunk(int cx, int cz, int y_lo, int cy, PackedByteArray data);
	bool has_chunk(int cx, int cz);
	void unload_chunk(int cx, int cz);
	PackedByteArray get_chunk_data(int cx, int cz);
	Vector2i get_chunk_range(int cx, int cz);
	int get_voxel(Vector3i p);
	void set_voxel(Vector3i p, int v);
	Dictionary mesh_region(Vector3i lo, Vector3i size, int lod, bool water, bool ao, Vector3 offset);
	PackedVector3Array collision_region(Vector3i lo, Vector3i size, Vector3 offset);
	Dictionary raycast(Vector3 from, Vector3 dir, float max_dist, bool hit_water);
	Dictionary carve_cluster(Vector3i at, Vector3i normal, int count, int max_hard, int seed, float jitter, Vector3i lo, Vector3i hi);
	Dictionary apply_object(Ref<VoxelObject> obj, Vector3i at, int mode, int pattern, bool natural);
	PackedInt32Array set_voxels(PackedInt32Array list);
	bool touches_solid(Ref<VoxelObject> obj, Vector3i at);
	int count_overlap(Ref<VoxelObject> obj, Vector3i at);
	Array find_islands(Vector3i lo, Vector3i hi, int limit);
	int column_top(int x, int z);
	Ref<VoxelObject> copy_region(Vector3i lo, Vector3i size);
	Dictionary foundation(Ref<VoxelObject> obj, Vector3i at, int max_depth);
	Dictionary apply_changes(PackedInt32Array list, int column);
	PackedInt32Array find_values(Vector3i center, int radius, PackedByteArray mask, int max_count);
};

} // namespace godot
