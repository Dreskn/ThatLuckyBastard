-- The Receipt theme: receipts in ink in the main window, till keys for
-- buttons, and everything back as it was when another theme is chosen.
Include("test_run.lua")
print("\n==== receipt theme ====")
local ns = NS
local db = ThatLuckyBastardDB
local function check(ok, what)
    print((ok and "  ok    " or "  FAIL  ") .. what)
    if not ok then FAILED = (FAILED or 0) + 1 end
end
local function drew(text)
    for _, t in ipairs(TEXTLOG) do
        if t:find(text, 1, true) then return true end
    end
    return false
end
-- The main window's columns that are on show.
local function columns()
    local out = {}
    for _, w in ipairs(FRAMES) do
        if rawget(w, "market") and rawget(w, "rows") and w:IsShown() then
            out[#out + 1] = w
        end
    end
    return out
end
-- A button made by ns.MakeButton, by its label.
local function button(label)
    for _, w in ipairs(FRAMES) do
        local tpl = rawget(w, "tpl")
        if type(tpl) == "table" and tpl.__text == label then return w end
    end
end
-- An option of the panel, by its label.
local function control(label)
    for _, w in ipairs(FRAMES) do
        local t = rawget(w, "text")
        if rawget(w, "get") and type(t) == "table" and t.__text == label then return w end
    end
end

print("-- choosing it")
check(ns.SetTheme("receipt") and db.theme == "receipt", "/tlb theme receipt picks it")
Fire("ADDON_LOADED", "ThatLuckyBastard")
check(db.theme == "receipt", "and it is kept when the game loads again")

local run = db.history[1]
WORLD.inInstance = false
db.options.useColumns = true
TEXTLOG = {}
ns.ShowRun(run)

print("-- the receipts")
local cols = columns()
check(#cols >= 2, "one receipt per player (" .. #cols .. ")")
local plain, ranks, grey, tails = true, 0, true, true
local heights = {}
for _, c in ipairs(cols) do
    if c.market.__text:find("|c", 1, true) then plain = false end
    if c.rank:IsShown() and c.rank.__text:match("^%*%*%* %d+%a%a %*%*%*$") then ranks = ranks + 1 end
    if c.portrait:IsShown() and not c.portrait:IsDesaturated() then grey = false end
    local t = rawget(c, "tail")
    if not (t and t.thanks:IsShown() and t.thanks.__text == "THANK YOU FOR LOOTING" and t.edge:IsShown()) then
        tails = false
    end
    heights[c.__h or 0] = true
end
local lengths = 0
for _ in pairs(heights) do lengths = lengths + 1 end
check(plain, "totals are printed plain, without the gold and silver colours")
check(ranks == #cols, "each says its place: *** 1ST *** and so on")
check(grey, "pictures are printed in grey")
check(tails, "each ends with a thank-you and a torn edge")
check(lengths > 1, "receipts end where their print does, at different lengths")
check(drew("KETT LONGSTRIDE") and drew("MIRA VALE"), "names in capitals")

local inked, bright, heading = false, false, false
for _, c in ipairs(cols) do
    for _, r in ipairs(c.rows) do
        local label = r.label.__text or ""
        if r:IsShown() and label:find("|Hitem:", 1, true) then
            if label:find("|cnIQ", 1, true) then bright = true end
            if label:match("^%d* ?|cff%x%x%x%x%x%x|Hitem:") then inked = true end
        end
        if r:IsShown() and r.line and r.line.cat and label == label:upper() and label ~= "" then heading = true end
    end
end
check(inked and not bright, "items are written in darker inks of their quality, still as links")
check(heading, "category headings in capitals")

local stamped = false
for _, c in ipairs(cols) do
    local af = rawget(c, "awardFrame")
    if af and af:IsShown() and af.edges[1]:IsShown() and not af.icon:IsShown() then stamped = true end
end
check(stamped, "awards are rubber stamps: a border in ink, no icon")
check(ns.Money(123456):find("|cffffd700", 1, true) ~= nil, "money in tooltips keeps its colours")

print("-- till keys")
local need, share = button("Need only"), button("Share")
check(need.key and need.flat.text.__text == "NEED ONLY" and need.flat.edge:IsShown(),
      "buttons are keys, labelled in capitals")
check(share.flat.text.__font == "ThatLuckyBastardReceiptKeyLight", "Share is a red key")
need.tpl.__scripts.OnClick(need.tpl)
check(need.selected and not need.flat.edge:IsShown(), "a key that is on is held down")
need.tpl.__scripts.OnClick(need.tpl)

print("-- the list on paper")
db.options.useColumns = false
TEXTLOG = {}
ns.Rerender()
check(drew("|cff2a2724KETT LONGSTRIDE|r"), "the list is printed in ink too")
db.options.useColumns = true

print("-- options")
ns.ToggleOptions()
check(control("Receipt") and control("Receipt").get(), "the Options offer it, ticked")
check(not control("Icons"):IsEnabled(), "item icons are greyed out: a receipt prints none")
control("Modern").__scripts.OnClick(control("Modern"))
check(db.theme == "modern" and control("Icons"):IsEnabled(), "back to Modern from the Options")
ns.ToggleOptions()

print("-- back to Modern")
TEXTLOG = {}
ns.Rerender()
cols = columns()
local gold, colour, notails = false, true, true
for _, c in ipairs(cols) do
    if c.market.__text:find("|cffffd700", 1, true) then gold = true end
    if c.portrait:IsDesaturated() then colour = false end
    local t = rawget(c, "tail")
    if t and t.thanks:IsShown() then notails = false end
end
check(gold and colour and notails, "totals in gold again, pictures in colour, no receipt ends")
check(not need.key and need.flat.text.__text == "Need only", "buttons are flat buttons again")

print(FAILED and (FAILED .. " check(s) FAILED") or "all checks passed (receipt theme)")
