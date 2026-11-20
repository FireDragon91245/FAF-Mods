// Appended to mesh.fx in process memory by FireDragon Core & Loader.
// Independent techniques: no stock shader or faction is replaced.
struct MODULAR_HEX_VERTEX
{
    float4 position : POSITION0;
    float edge : TEXCOORD0;
    float4 material : TEXCOORD2;
    float2 maskDepth : TEXCOORD3;
};

MODULAR_HEX_VERTEX ModularHexVS(
    float3 position : POSITION0,
    float3 normal : NORMAL0,
    float3 unusedTangent : TANGENT,
    float3 unusedBinormal : BINORMAL,
    float4 texcoord : TEXCOORD0,
    int boneIndex[4] : BLENDINDICES,
    float3 row0 : TEXCOORD1,
    float3 row1 : TEXCOORD2,
    float3 row2 : TEXCOORD3,
    float3 row3 : TEXCOORD4,
    anim_t anim : TEXCOORD5,
    float4 material : TEXCOORD6,
    float4 color : COLOR0)
{
    MODULAR_HEX_VERTEX v = (MODULAR_HEX_VERTEX)0;
    // Identity-bone effect mesh. Both overlays and dome use the same rotating
    // geodesic cells. Entity orientation encodes only the hit direction, so an
    // oriented overlay never rotates its cell borders away from the main dome.
    float scale = length(row0);
    // Engine time is interpolated simulation ticks, wrapped at 36000 ticks.
    // One revolution per 1200 ticks = 120 seconds at the ideal 10 ticks/second.
    // 1200 divides the clock's wrap period, so rotation stays continuous there.
    // Dome and impact overlays share this phase and follow sim speed/pause.
    float angle = frac(time / 1200.0) * 6.28318530718;
    float s = sin(angle), c = cos(angle);
    float3 n = normalize(position);
    float3 rotated = float3(c*n.x - s*n.z, n.y, s*n.x + c*n.z);
    float4 p = float4(rotated * (0.5*scale) + row3, 1);
    v.position = mul(p, mul(viewMatrix, projMatrix));
    v.edge = texcoord.x;
    v.material = float4(time - material.x, material.yzw);
    v.maskDepth = float2(dot(rotated, normalize(row2)), p.y - surfaceElevation);
    return v;
}

float ModularHexLines(MODULAR_HEX_VERTEX v)
{
    // Each cell fan interpolates 0 at its center and 1 at the shared border.
    // No spherical UVs, periodic sampling, projection blends or wrap seam.
    return smoothstep(0.94, 0.985, v.edge);
}

float4 ModularHexDomePS(MODULAR_HEX_VERTEX v) : COLOR0
{
    if (1 == mirrored) clip(v.maskDepth.y);
    float hp = saturate(v.material.y);
    float3 warm = lerp(float3(1,0.07,0.025), float3(1,0.72,0.08), saturate((hp-0.15)*5));
    float3 tint = lerp(warm, float3(0.055,0.42,1), saturate((hp-0.55)*5));
    float seam = ModularHexLines(v);
    float breath = 0.93 + 0.07*sin(time*1.8);
    // Mostly transparent faces, readable luminous seams; no opaque inner shell.
    float alpha = (0.018 + seam*0.23) * shieldWaterAbsorption(v.maskDepth.y);
    return float4(tint*(0.5 + seam*1.6)*breath, alpha);
}

float4 ModularHexHitPS(MODULAR_HEX_VERTEX v, uniform float3 tint) : COLOR0
{
    if (1 == mirrored) clip(v.maskDepth.y);
    float seam = ModularHexLines(v);
    float patch = saturate((v.maskDepth.x-0.90)*10);
    float fade = saturate(1-v.material.x/0.85);
    float flash = patch*patch*fade*fade;
    float alpha = flash*(0.18 + seam*0.82)*shieldWaterAbsorption(v.maskDepth.y);
    return float4(lerp(tint, float3(0.8,0.94,1), seam*0.55)*2.3, alpha);
}

technique ModularHexDome
<
    string cartographicTechnique = "CartographicShield";
    int renderStage = STAGE_POSTWATER + STAGE_POSTEFFECT;
    int parameter = PARAM_FRACTIONHEALTH;
>
{
    pass P0
    {
        AlphaState(AlphaBlend_SrcAlpha_InvSrcAlpha_Write_RGB)
        RasterizerState(Rasterizer_Cull_CW)
        DepthState(Depth_Enable_LessEqual_Write_None)
        VertexShader = compile vs_2_0 ModularHexVS();
        PixelShader = compile ps_2_0 ModularHexDomePS();
    }
}

technique ModularHexHitBlue
< int renderStage = STAGE_POSTWATER + STAGE_POSTEFFECT; int parameter = PARAM_UNUSED; >
{
    pass P0
    {
        AlphaState(AlphaBlend_SrcAlpha_One_Write_RGB)
        RasterizerState(Rasterizer_Cull_CW)
        DepthState(Depth_Enable_LessEqual_Write_None)
        VertexShader = compile vs_2_0 ModularHexVS();
        PixelShader = compile ps_2_0 ModularHexHitPS(float3(0.055,0.42,1));
    }
}
technique ModularHexHitYellow
< int renderStage = STAGE_POSTWATER + STAGE_POSTEFFECT; int parameter = PARAM_UNUSED; >
{
    pass P0
    {
        AlphaState(AlphaBlend_SrcAlpha_One_Write_RGB)
        RasterizerState(Rasterizer_Cull_CW)
        DepthState(Depth_Enable_LessEqual_Write_None)
        VertexShader = compile vs_2_0 ModularHexVS();
        PixelShader = compile ps_2_0 ModularHexHitPS(float3(1,0.72,0.08));
    }
}
technique ModularHexHitRed
< int renderStage = STAGE_POSTWATER + STAGE_POSTEFFECT; int parameter = PARAM_UNUSED; >
{
    pass P0
    {
        AlphaState(AlphaBlend_SrcAlpha_One_Write_RGB)
        RasterizerState(Rasterizer_Cull_CW)
        DepthState(Depth_Enable_LessEqual_Write_None)
        VertexShader = compile vs_2_0 ModularHexVS();
        PixelShader = compile ps_2_0 ModularHexHitPS(float3(1,0.07,0.025));
    }
}
