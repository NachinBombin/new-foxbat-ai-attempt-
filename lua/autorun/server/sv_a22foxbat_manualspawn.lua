if not SERVER then return end

util.AddNetworkString("A22Foxbat_ManualSpawn")

net.Receive("A22Foxbat_ManualSpawn", function(len, ply)
    if not IsValid(ply) then return end

    local tr = util.TraceLine({
        start  = ply:EyePos(),
        endpos = ply:EyePos() + ply:EyeAngles():Forward() * 3000,
        filter = ply,
    })

    local centerPos = tr.Hit and tr.HitPos or (ply:GetPos() + Vector(0, 0, 100))
    local callDir   = ply:EyeAngles():Forward()
    callDir.z = 0
    if callDir:LengthSqr() <= 1 then callDir = Vector(1, 0, 0) end
    callDir:Normalize()

    if not scripted_ents.GetStored("ent_a22foxbat") then
        ply:PrintMessage(HUD_PRINTCENTER, "[A22 Foxbat] Entity not registered!")
        return
    end

    local ent = ents.Create("ent_a22foxbat")
    if not IsValid(ent) then
        ply:PrintMessage(HUD_PRINTCENTER, "[A22 Foxbat] Spawn failed!")
        return
    end

    ent:SetPos(centerPos)
    ent:SetAngles(callDir:Angle())
    ent:SetVar("CenterPos",           centerPos)
    ent:SetVar("CallDir",             callDir)
    ent:SetVar("Lifetime",            GetConVar("npc_a22foxbat_lifetime"):GetFloat())
    ent:SetVar("Speed",               GetConVar("npc_a22foxbat_speed"):GetFloat())
    ent:SetVar("OrbitRadius",         GetConVar("npc_a22foxbat_radius"):GetFloat())
    ent:SetVar("SkyHeightAdd",        GetConVar("npc_a22foxbat_height"):GetFloat())
    ent:SetVar("DIVE_ExplosionDamage", GetConVar("npc_a22foxbat_dive_damage"):GetFloat())
    ent:SetVar("DIVE_ExplosionRadius", GetConVar("npc_a22foxbat_dive_radius"):GetFloat())
    ent:Spawn()
    ent:Activate()

    ply:PrintMessage(HUD_PRINTCENTER, "[A22 Foxbat] Foxbat inbound!")
end)
