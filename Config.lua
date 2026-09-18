-- Panneau d'options (Interface > AddOns > KickAlert). Widgets Blizzard uniquement, pas de lib.
-- Chaque réglage est appliqué immédiatement, sans /reload.
local _, NS = ...
local L = NS.L

local panel = CreateFrame("Frame", "KickAlertOptions")
panel:Hide()

local refreshers = {}       -- widgets à resynchroniser depuis NS.db à l'ouverture
local refreshing = false    -- évite que Refresh() déclenche les setters
local widgetCount = 0
local function NextName()
    widgetCount = widgetCount + 1
    return "KickAlertOption" .. widgetCount
end

local function Column(x)
    return { x = x, y = -16 }
end

local function Place(col, frame, height, offsetX)
    frame:SetPoint("TOPLEFT", panel, "TOPLEFT", col.x + (offsetX or 0), col.y)
    col.y = col.y - height
end

local function Title(col, text)
    local fs = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    fs:SetText(text)
    col.y = col.y - 8
    Place(col, fs, 30)
end

local function Check(col, label, get, set)
    local cb = CreateFrame("CheckButton", NextName(), panel, "UICheckButtonTemplate")
    local text = _G[cb:GetName() .. "Text"] or cb.Text or cb.text
    if not text then
        text = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    end
    text:SetText(label)
    text:SetFontObject("GameFontHighlight")
    cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    refreshers[#refreshers + 1] = function() cb:SetChecked(get()) end
    Place(col, cb, 28, -4)
    return cb
end

local function Slider(col, label, minValue, maxValue, step, get, set)
    local s = CreateFrame("Slider", NextName(), panel, "OptionsSliderTemplate")
    s:SetWidth(240)
    s:SetMinMaxValues(minValue, maxValue)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    local low, high = _G[s:GetName() .. "Low"], _G[s:GetName() .. "High"]
    if low then low:SetText(minValue) end
    if high then high:SetText(maxValue) end
    local text = _G[s:GetName() .. "Text"]
    if not text then
        text = s:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        text:SetPoint("BOTTOM", s, "TOP", 0, 2)
    end
    local function paint(value) text:SetText(label .. " : " .. value) end
    s:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value / step + 0.5) * step
        paint(value)
        if not refreshing then set(value) end
    end)
    -- SetValue ne déclenche rien si la valeur est déjà celle du widget (ex. valeur mini) : peindre explicitement.
    refreshers[#refreshers + 1] = function() s:SetValue(get()); paint(get()) end
    col.y = col.y - 14
    Place(col, s, 40, 6)
    return s
end

local function Edit(col, label, get, set)
    local fs = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    fs:SetText(label)
    Place(col, fs, 18)
    local eb = CreateFrame("EditBox", NextName(), panel, "InputBoxTemplate")
    eb:SetSize(240, 24)
    eb:SetAutoFocus(false)
    eb:SetScript("OnEnterPressed", function(self)
        set(self:GetText())
        self:ClearFocus()
    end)
    eb:SetScript("OnEscapePressed", function(self)
        self:SetText(get())
        self:ClearFocus()
    end)
    refreshers[#refreshers + 1] = function() eb:SetText(get()) end
    Place(col, eb, 32, 8)
    return eb
end

local function Color(col, label, color, onChange)
    local b = CreateFrame("Button", NextName(), panel)
    b:SetSize(240, 24)
    local swatch = b:CreateTexture(nil, "ARTWORK")
    swatch:SetSize(20, 20)
    swatch:SetPoint("LEFT")
    NS.SetSolidColor(swatch, 1, 1, 1, 1)
    local border = b:CreateTexture(nil, "BACKGROUND")
    border:SetPoint("TOPLEFT", swatch, -1, 1)
    border:SetPoint("BOTTOMRIGHT", swatch, 1, -1)
    NS.SetSolidColor(border, 0.6, 0.6, 0.6, 1)
    local text = b:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("LEFT", swatch, "RIGHT", 8, 0)
    text:SetText(label)
    local function paint() NS.SetSolidColor(swatch, color.r, color.g, color.b, 1) end
    b:SetScript("OnClick", function()
        NS.OpenColorPicker(color, function()
            paint()
            onChange()
        end)
    end)
    refreshers[#refreshers + 1] = paint
    Place(col, b, 28, 4)
    return b
end

-- Bouton cyclique : clic gauche = suivant, clic droit = précédent. options = { {name=, value=}, ... }.
local function Cycle(col, label, options, get, set)
    local b = CreateFrame("Button", NextName(), panel, "UIPanelButtonTemplate")
    b:SetSize(240, 24)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local function indexOf(value)
        for i = 1, #options do
            if options[i].value == value then return i end
        end
        return 1
    end
    local function paint()
        local current = get()
        local i = indexOf(current)
        local name = options[i].value == current and options[i].name or tostring(current)
        b:SetText(label .. " : " .. name)
    end
    b:SetScript("OnClick", function(_, button)
        local i = indexOf(get()) + (button == "RightButton" and -1 or 1)
        if i > #options then i = 1 elseif i < 1 then i = #options end
        set(options[i].value)
        paint()
    end)
    refreshers[#refreshers + 1] = paint
    Place(col, b, 30, 4)
    return b
end

local function Button(col, label, onClick)
    local b = CreateFrame("Button", NextName(), panel, "UIPanelButtonTemplate")
    b:SetSize(240, 24)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    Place(col, b, 30, 4)
    return b
end

---------------------------------------------------------------------------
-- Construction du panneau (une fois la DB prête, les getters lisent NS.db)
---------------------------------------------------------------------------
local function ApplyText()
    NS.Text:Apply()
    NS.Text:Refresh()
end

local function Build()
    local db = NS.db
    local left, right = Column(16), Column(330)

    local header = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
    header:SetText("KickAlert")
    Place(left, header, 26)
    local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetText(L.CFG_SUBTITLE)
    Place(left, sub, 20)
    right.y = left.y

    -- Colonne gauche : déclenchement + texte
    Title(left, L.CFG_TRIGGER)
    if NS.has.focus then
        Check(left, L.CFG_WATCH_FOCUS, function() return db.watchFocus end,
            function(v) db.watchFocus = v; NS.Detector:UpdateWatchedGUIDs(); NS.Detector:Wake() end)
    end
    Check(left, L.CFG_ONLY_READY, function() return db.onlyWhenReady end,
        function(v) db.onlyWhenReady = v; NS.Detector:Wake() end)
    Check(left, L.CFG_CHECK_RANGE, function() return db.checkRange end,
        function(v) db.checkRange = v; NS.Detector:Wake() end)

    Title(left, L.CFG_TEXT)
    Check(left, L.CFG_TEXT_ENABLE, function() return db.text.enabled end,
        function(v) db.text.enabled = v; ApplyText() end)
    Edit(left, L.CFG_TEXT_LABEL, function() return db.text.label end,
        function(v) db.text.label = v; ApplyText() end)
    local fonts = {}
    for _, f in ipairs(NS.GetFontList()) do fonts[#fonts + 1] = { name = f.name, value = f.path } end
    Cycle(left, L.CFG_FONT, fonts, function() return db.text.font end,
        function(v) db.text.font = v; ApplyText() end)
    Cycle(left, L.CFG_OUTLINE, {
        { name = L.OUTLINE_NONE, value = "NONE" },
        { name = L.OUTLINE_THIN, value = "OUTLINE" },
        { name = L.OUTLINE_THICK, value = "THICKOUTLINE" },
    }, function() return db.text.outline end, function(v) db.text.outline = v; ApplyText() end)
    Slider(left, L.CFG_SIZE, 12, 128, 2, function() return db.text.size end,
        function(v) db.text.size = v; ApplyText() end)
    Color(left, L.CFG_TEXT_COLOR, db.text.color, ApplyText)
    Check(left, L.CFG_TEXT_PULSE, function() return db.text.pulse end,
        function(v) db.text.pulse = v; ApplyText() end)
    Slider(left, L.CFG_PULSE_SPEED, 0.5, 6, 0.5, function() return db.text.pulseSpeed end,
        function(v) db.text.pulseSpeed = v end)

    if NS.has.namePlates and NS.has.namePlateUnits then
        Title(left, L.CFG_NAMEPLATES)
        Check(left, L.CFG_NAMEPLATES_ENABLE, function() return db.nameplate.enabled end,
            function(v) db.nameplate.enabled = v; NS.Nameplate:RefreshAll() end)
        Cycle(left, L.CFG_FONT, fonts, function() return db.nameplate.text.font end,
            function(v) db.nameplate.text.font = v; NS.Nameplate:RefreshAll() end)
        Slider(left, L.CFG_SIZE, 8, 48, 1, function() return db.nameplate.text.size end,
            function(v) db.nameplate.text.size = v; NS.Nameplate:RefreshAll() end)
        Color(left, L.CFG_COLOR, db.nameplate.text.color, function() NS.Nameplate:RefreshAll() end)
    end

    -- Colonne droite : halo + son
    Title(right, L.CFG_AURA)
    Check(right, L.CFG_AURA_ENABLE, function() return db.aura.enabled end,
        function(v) db.aura.enabled = v; NS.Aura:Refresh() end)
    Color(right, L.CFG_AURA_COLOR, db.aura.color, function() NS.Aura:Refresh() end)
    Slider(right, L.CFG_THICKNESS, 20, 400, 10, function() return db.aura.thickness end,
        function(v) db.aura.thickness = v; NS.Aura:Refresh() end)
    Check(right, L.CFG_AURA_PULSE, function() return db.aura.pulse end,
        function(v) db.aura.pulse = v; NS.Aura:Refresh() end)
    Slider(right, L.CFG_PULSE_SPEED, 0.5, 6, 0.5, function() return db.aura.pulseSpeed end,
        function(v) db.aura.pulseSpeed = v end)

    Title(right, L.CFG_SOUND)
    Check(right, L.CFG_SOUND_ENABLE, function() return db.sound.enabled end,
        function(v) db.sound.enabled = v end)
    local presets = {}
    for _, name in ipairs(NS.SOUND_PRESET_ORDER) do presets[#presets + 1] = { name = name, value = name } end
    Cycle(right, L.CFG_SOUND, presets, function() return db.sound.sound end,
        function(v) db.sound.sound = v; NS.Sound:Play(true) end)
    Edit(right, L.CFG_SOUND_CUSTOM,
        function() return tostring(db.sound.sound or "") end,
        function(v)
            if v ~= "" then db.sound.sound = tonumber(v) or v end
            NS.Sound:Play(true)
        end)
    Button(right, L.CFG_SOUND_TEST, function() NS.Sound:Play(true) end)

    Title(right, L.CFG_TEST)
    Button(right, L.CFG_TEST_PREVIEW, function() NS:Test() end)
    Button(right, L.CFG_TEST_MOVE, function() NS:SetUnlocked(not NS.unlocked) end)
end

panel:SetScript("OnShow", function()
    refreshing = true
    for i = 1, #refreshers do refreshers[i]() end
    refreshing = false
    NS.Text:Refresh()
    NS.Aura:Refresh()
end)
panel:SetScript("OnHide", function()
    NS.Text:Refresh()
    NS.Aura:Refresh()
end)

NS:On("DB_READY", function()
    Build()
    NS.RegisterOptionsPanel(panel, "KickAlert")
end)
