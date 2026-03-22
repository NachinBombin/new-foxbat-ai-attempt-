if not CLIENT then return end

-- ============================================================
-- SPAWNLIST REGISTRATION (under Bombin Support tree)
-- ============================================================

hook.Add("PopulateContent", "A22Foxbat_SpawnMenu", function(pnlContent, tree, node)
    local node = tree:AddNode("Bombin Support", "icon16/bomb.png")

    node:MakePopulator(function(pnlContent)
        local icon = vgui.Create("ContentIcon", pnlContent)
        icon:SetContentType("entity")
        icon:SetSpawnName("ent_a22foxbat")
        icon:SetName("A22 Foxbat")
        icon:SetMaterial("entities/ent_a22foxbat.png")
        icon:SetToolTip("Autonomous A22 Foxbat loiter munition.\nFlies freely until a target is found, then dives and explodes.")
        pnlContent:Add(icon)
    end)
end)

-- ============================================================
-- CONSOLE COMMAND — manual test spawn
-- ============================================================

concommand.Add("foxbat_spawn", function()
    if not IsValid(LocalPlayer()) then return end
    net.Start("A22Foxbat_ManualSpawn")
    net.SendToServer()
end)

-- ============================================================
-- CONTROL PANEL
-- ============================================================

hook.Add("AddToolMenuTabs", "A22Foxbat_Tab", function()
    spawnmenu.AddToolTab("Bombin Support", "Bombin Support", "icon16/bomb.png")
end)

hook.Add("AddToolMenuCategories", "A22Foxbat_Categories", function()
    spawnmenu.AddToolCategory("Bombin Support", "A22 Foxbat", "A22 Foxbat")
end)

hook.Add("PopulateToolMenu", "A22Foxbat_ToolMenu", function()
    spawnmenu.AddToolMenuOption("Bombin Support", "A22 Foxbat", "a22foxbat_settings", "A22 Foxbat Settings", "", "", function(panel)
        panel:ClearControls()
        panel:Help("NPC Call Settings")

        panel:CheckBox("Enable NPC calls", "npc_a22foxbat_enabled")

        panel:NumSlider("Call chance (per check)",      "npc_a22foxbat_chance",    0,   1,    2)
        panel:NumSlider("Check interval (seconds)",     "npc_a22foxbat_interval",  1,   60,   0)
        panel:NumSlider("NPC cooldown (seconds)",       "npc_a22foxbat_cooldown",  10,  300,  0)
        panel:NumSlider("Min call distance (HU)",       "npc_a22foxbat_min_dist",  100, 1000, 0)
        panel:NumSlider("Max call distance (HU)",       "npc_a22foxbat_max_dist",  500, 8000, 0)
        panel:NumSlider("Flare → arrival delay (s)",   "npc_a22foxbat_delay",     1,   30,   0)

        panel:Help("Munition Behaviour")
        panel:NumSlider("Lifetime (seconds)",           "npc_a22foxbat_lifetime",  10,  120,  0)
        panel:NumSlider("Flight speed (HU/s)",          "npc_a22foxbat_speed",     50,  800,  0)
        panel:NumSlider("Containment radius (HU)",      "npc_a22foxbat_radius",    500, 6000, 0)
        panel:NumSlider("Spawn altitude above ground (HU)", "npc_a22foxbat_height", 500, 8000, 0)

        panel:Help("Dive Attack")
        panel:NumSlider("Explosion damage",             "npc_a22foxbat_dive_damage", 50,  1000, 0)
        panel:NumSlider("Explosion radius (HU)",        "npc_a22foxbat_dive_radius", 100, 2000, 0)

        panel:Help("Debug")
        panel:CheckBox("Enable debug prints", "npc_a22foxbat_announce")

        panel:Help("Manual spawn (for testing)")
        panel:Button("Spawn A22 Foxbat now", "foxbat_spawn")
    end)
end)
