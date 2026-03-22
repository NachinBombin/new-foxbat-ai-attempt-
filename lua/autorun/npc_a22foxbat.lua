AddCSLuaFile()

if SERVER then

    util.AddNetworkString( "A22Foxbat_FlareSpawned" )

    -- ============================================================
    -- ConVars
    -- ============================================================

    local NFP_FLAGS = bit.bor( FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY )

    local cv_enabled     = CreateConVar( "npc_a22foxbat_enabled",      "1",    NFP_FLAGS, "Enable/disable A22 Foxbat calls" )
    local cv_chance      = CreateConVar( "npc_a22foxbat_chance",       "0.12", NFP_FLAGS, "Probability per NPC check (0.0–1.0)" )
    local cv_interval    = CreateConVar( "npc_a22foxbat_interval",     "12",   NFP_FLAGS, "Seconds between per-NPC eligibility checks" )
    local cv_cooldown    = CreateConVar( "npc_a22foxbat_cooldown",     "50",   NFP_FLAGS, "Per-NPC cooldown in seconds after a successful call" )
    local cv_max_dist    = CreateConVar( "npc_a22foxbat_max_dist",     "3000", NFP_FLAGS, "Max NPC-to-player distance to allow a call (HU)" )
    local cv_min_dist    = CreateConVar( "npc_a22foxbat_min_dist",     "400",  NFP_FLAGS, "Min NPC-to-player distance to allow a call (HU)" )
    local cv_delay       = CreateConVar( "npc_a22foxbat_delay",        "5",    NFP_FLAGS, "Seconds from flare throw to plane arrival" )
    local cv_life        = CreateConVar( "npc_a22foxbat_lifetime",     "40",   NFP_FLAGS, "Plane lifetime in seconds before auto-removal" )
    local cv_speed       = CreateConVar( "npc_a22foxbat_speed",        "250",  NFP_FLAGS, "Plane cruise speed HU/s" )
    local cv_radius      = CreateConVar( "npc_a22foxbat_radius",       "2500", NFP_FLAGS, "Patrol turn radius HU (from spawn center)" )
    local cv_height      = CreateConVar( "npc_a22foxbat_height",       "2500", NFP_FLAGS, "Spawn altitude above ground HU" )
    local cv_dive_damage = CreateConVar( "npc_a22foxbat_dive_damage",  "350",  NFP_FLAGS, "Dive explosion damage" )
    local cv_dive_radius = CreateConVar( "npc_a22foxbat_dive_radius",  "600",  NFP_FLAGS, "Dive explosion radius HU" )
    local cv_announce    = CreateConVar( "npc_a22foxbat_announce",     "0",    NFP_FLAGS, "Enable debug print messages" )

    -- ============================================================
    -- NPC classes that can call the plane
    -- ============================================================

    local NFP_CALLERS = {
        ["npc_combine_s"]     = true,
        ["npc_metropolice"]   = true,
        ["npc_combine_elite"] = true,
    }

    -- ============================================================
    -- HELPERS
    -- ============================================================

    local function NFP_Debug( nfpMsg )
        if not cv_announce:GetBool() then return end
        local nfpFull = "[A22 Foxbat] " .. tostring( nfpMsg )
        print( nfpFull )
        for _, nfpPly in ipairs( player.GetHumans() ) do
            if IsValid( nfpPly ) then nfpPly:PrintMessage( HUD_PRINTCONSOLE, nfpFull ) end
        end
    end

    -- Returns true if there is open sky (or only one thin ceiling) above pos.
    local function NFP_CheckSkyAbove( nfpPos )
        local nfpTr = util.TraceLine({
            start  = nfpPos + Vector(0, 0, 50),
            endpos = nfpPos + Vector(0, 0, 1050),
        })
        if nfpTr.Hit and not nfpTr.HitSky then
            nfpTr = util.TraceLine({
                start  = nfpTr.HitPos + Vector(0, 0, 50),
                endpos = nfpTr.HitPos + Vector(0, 0, 1000),
            })
        end
        return not (nfpTr.Hit and not nfpTr.HitSky)
    end

    -- Throws a blue flare from the NPC toward the target.
    -- Returns the flare entity, or nil on failure.
    local function NFP_ThrowFlare( nfpNPC, nfpTargetPos )
        local nfpEyePos  = nfpNPC:EyePos()
        local nfpToTgt   = (nfpTargetPos - nfpEyePos):GetNormalized()

        local nfpFlare = ents.Create( "ent_bombin_flare_blue" )
        if not IsValid( nfpFlare ) then
            NFP_Debug( "Flare spawn failed" )
            return nil
        end

        nfpFlare:SetPos( nfpEyePos + nfpToTgt * 52 )
        nfpFlare:SetAngles( nfpNPC:GetAngles() )
        nfpFlare:Spawn()
        nfpFlare:Activate()

        local nfpDir  = nfpTargetPos - nfpFlare:GetPos()
        local nfpDist = nfpDir:Length()
        nfpDir:Normalize()

        timer.Simple( 0, function()
            if not IsValid( nfpFlare ) then return end
            local nfpPhys = nfpFlare:GetPhysicsObject()
            if not IsValid( nfpPhys ) then return end
            nfpPhys:SetVelocity( nfpDir * 700 + Vector(0, 0, nfpDist * 0.25) )
            nfpPhys:Wake()
        end )

        net.Start( "A22Foxbat_FlareSpawned" )
        net.WriteEntity( nfpFlare )
        net.Broadcast()

        NFP_Debug( "Flare thrown toward " .. tostring(nfpTargetPos) )
        return nfpFlare
    end

    -- Creates and configures the ent_a22foxbat at the given position.
    local function NFP_SpawnPlane( nfpCenterPos, nfpCallDir )
        if not scripted_ents.GetStored( "ent_a22foxbat" ) then
            NFP_Debug( "ent_a22foxbat not registered — is the entity folder loaded?" )
            return false
        end

        local nfpEnt = ents.Create( "ent_a22foxbat" )
        if not IsValid( nfpEnt ) then
            NFP_Debug( "ents.Create returned invalid entity" )
            return false
        end

        nfpEnt:SetPos( nfpCenterPos )
        nfpEnt:SetAngles( nfpCallDir:Angle() )

        -- Configuration vars passed into Initialize() via GetVar()
        nfpEnt:SetVar( "CenterPos",            nfpCenterPos )
        nfpEnt:SetVar( "CallDir",              nfpCallDir )
        nfpEnt:SetVar( "Lifetime",             cv_life:GetFloat() )
        nfpEnt:SetVar( "Speed",                cv_speed:GetFloat() )
        nfpEnt:SetVar( "OrbitRadius",          cv_radius:GetFloat() )
        nfpEnt:SetVar( "SkyHeightAdd",         cv_height:GetFloat() )
        nfpEnt:SetVar( "DIVE_ExplosionDamage", cv_dive_damage:GetFloat() )
        nfpEnt:SetVar( "DIVE_ExplosionRadius", cv_dive_radius:GetFloat() )

        nfpEnt:Spawn()
        nfpEnt:Activate()

        if not IsValid( nfpEnt ) then
            NFP_Debug( "Entity invalid after Spawn()" )
            return false
        end

        NFP_Debug( "Plane spawned at " .. tostring( nfpCenterPos ) )
        return true
    end

    -- Full call sequence: validate, throw flare, schedule plane.
    local function NFP_FireCall( nfpNPC, nfpTarget )
        if not IsValid( nfpNPC ) then
            NFP_Debug( "NPC invalid" ) return false
        end
        if not IsValid( nfpTarget ) or not nfpTarget:IsPlayer() or not nfpTarget:Alive() then
            NFP_Debug( "Target invalid" ) return false
        end

        local nfpTargetPos = nfpTarget:GetPos() + Vector(0, 0, 36)

        if not NFP_CheckSkyAbove( nfpTargetPos ) then
            NFP_Debug( "No open sky above target — call aborted" ) return false
        end

        local nfpCallDir = nfpTargetPos - nfpNPC:GetPos()
        nfpCallDir.z = 0
        if nfpCallDir:LengthSqr() <= 1 then nfpCallDir = nfpNPC:GetForward() nfpCallDir.z = 0 end
        if nfpCallDir:LengthSqr() <= 1 then nfpCallDir = Vector(1, 0, 0) end
        nfpCallDir:Normalize()

        local nfpFlare = NFP_ThrowFlare( nfpNPC, nfpTargetPos )
        if not IsValid( nfpFlare ) then
            NFP_Debug( "Flare failed — aborting call" ) return false
        end

        -- Snapshot positions in case flare or NPC are gone when timer fires
        local nfpFallback  = Vector( nfpTargetPos.x, nfpTargetPos.y, nfpTargetPos.z )
        local nfpStoredDir = Vector( nfpCallDir.x,   nfpCallDir.y,   nfpCallDir.z )

        timer.Simple( cv_delay:GetFloat(), function()
            local nfpCenter = IsValid( nfpFlare ) and nfpFlare:GetPos() or nfpFallback
            NFP_SpawnPlane( nfpCenter, nfpStoredDir )
        end )

        return true
    end

    -- ============================================================
    -- MAIN POLL TIMER  (runs every 0.5s)
    -- ============================================================

    timer.Create( "A22Foxbat_Think", 0.5, 0, function()
        if not cv_enabled:GetBool() then return end

        local nfpNow      = CurTime()
        local nfpInterval = math.max( 1, cv_interval:GetFloat() )

        for _, nfpNPC in ipairs( ents.GetAll() ) do
            if not IsValid( nfpNPC ) then continue end
            if not NFP_CALLERS[ nfpNPC:GetClass() ] then continue end

            -- First time we see this NPC: stagger its first check
            if not nfpNPC.__nfp_hooked then
                nfpNPC.__nfp_hooked    = true
                nfpNPC.__nfp_nextCheck = nfpNow + math.Rand( 1, nfpInterval )
                nfpNPC.__nfp_lastCall  = 0
            end

            if nfpNow < nfpNPC.__nfp_nextCheck then continue end

            -- Reschedule next check with small jitter
            local nfpJitter = math.min( 2, nfpInterval * 0.5 )
            nfpNPC.__nfp_nextCheck = nfpNow + nfpInterval + math.Rand( -nfpJitter, nfpJitter )

            -- Gate checks
            if nfpNow - nfpNPC.__nfp_lastCall < cv_cooldown:GetFloat() then continue end
            if nfpNPC:Health() <= 0 then continue end

            local nfpEnemy = nfpNPC:GetEnemy()
            if not IsValid( nfpEnemy ) or not nfpEnemy:IsPlayer() or not nfpEnemy:Alive() then continue end

            local nfpDist = nfpNPC:GetPos():Distance( nfpEnemy:GetPos() )
            if nfpDist > cv_max_dist:GetFloat() or nfpDist < cv_min_dist:GetFloat() then continue end

            if math.random() > cv_chance:GetFloat() then continue end

            if NFP_FireCall( nfpNPC, nfpEnemy ) then
                nfpNPC.__nfp_lastCall = nfpNow
                NFP_Debug( "Call accepted — NPC targeting " .. nfpEnemy:GetName() )
            end
        end
    end )

end -- SERVER

-- ============================================================
-- CLIENT — blue dynamic light on the flare
-- ============================================================

if CLIENT then

    local nfp_activeFlares = {}

    net.Receive( "A22Foxbat_FlareSpawned", function()
        local nfpFlare = net.ReadEntity()
        if IsValid( nfpFlare ) then
            nfp_activeFlares[ nfpFlare:EntIndex() ] = nfpFlare
        end
    end )

    hook.Add( "Think", "A22Foxbat_FlareLight", function()
        for nfpIdx, nfpFlare in pairs( nfp_activeFlares ) do
            if not IsValid( nfpFlare ) then
                nfp_activeFlares[ nfpIdx ] = nil
                continue
            end

            local nfpDL = DynamicLight( nfpFlare:EntIndex() )
            if nfpDL then
                nfpDL.Pos        = nfpFlare:GetPos()
                nfpDL.r          = 0
                nfpDL.g          = 80
                nfpDL.b          = 255
                nfpDL.Brightness = (math.random() > 0.4) and math.Rand(4.0, 6.0) or math.Rand(0.0, 0.2)
                nfpDL.Size       = 55
                nfpDL.Decay      = 3000
                nfpDL.DieTime    = CurTime() + 0.05
            end
        end
    end )

end -- CLIENT
