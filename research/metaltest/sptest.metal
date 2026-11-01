#include <metal_stdlib>
using namespace metal;

kernel void sptest(device uint *out [[buffer(0)]], device float *fout [[buffer(1)]],
                   uint i [[thread_position_in_grid]]) {
  out[i] = i * 3 + 0x1234;
  fout[i] = sqrt(float(i)) * 0.5f + 1.0f;
}

struct VOut { float4 pos [[position]]; float4 col; };

vertex VOut spvert(uint vid [[vertex_id]]) {
  float2 p = float2((vid << 1) & 2, vid & 2);  // fullscreen triangle
  VOut o;
  o.pos = float4(p * 2.0f - 1.0f, 0.0f, 1.0f);
  o.col = float4(0.25f, 0.5f, 0.75f, 1.0f);
  return o;
}

fragment float4 spfrag(VOut in [[stage_in]], texture2d<float> tex [[texture(0)]]) {
  constexpr sampler s(filter::linear);
  return in.col * tex.sample(s, float2(0.5f));
}
