--[[
	KONUM: StarterPlayer > StarterPlayerScripts > LocalScript
	Arayüzün tamamı kodla kurulur, ekstra bir şey eklemene gerek yok.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local oyuncu = Players.LocalPlayer

-- Boş bırakırsan herkes kullanır. Sadece belirli kişiler için UserId yaz: {12345678, 87654321}
local YETKILI_IDLER = {}

local function yetkiliMi()
	if #YETKILI_IDLER == 0 then
		return true
	end
	for _, id in ipairs(YETKILI_IDLER) do
		if id == oyuncu.UserId then
			return true
		end
	end
	return false
end

if not yetkiliMi() then
	return
end

-- =========================================================
-- RENKLER VE DURUM DEĞİŞKENLERİ
-- =========================================================
local ARKA = Color3.fromRGB(28, 28, 36)
local KOYU = Color3.fromRGB(40, 40, 52)
local PASIF = Color3.fromRGB(58, 58, 74)
local AKTIF = Color3.fromRGB(46, 160, 90)
local YAZI = Color3.fromRGB(255, 255, 255)
local VARSAYILAN_YERCEKIMI = Workspace.Gravity
local rnd = Random.new()

local ayar = {
	HizDeger = nil,
	ZiplamaDeger = nil,
	YercekimiDeger = nil,
	DusmeLimiti = 0,
	Zigzag = false,
	ZigzagGenislik = 2,
	ZigzagSiklik = 20,
}
local zigzagFaz = 0
local zigzagOnceki = 0
local zigzagYon = Vector3.new(0, 0, 0)

local hedef = nil
local hedefEtiketleri = {}
local oyuncuButonlari = {}
local mesgul = false
local takipAcik = false

local aktifMod = nil
local modZaman = 0
local modSayac = 0
local origC0 = {}
local origHip = 0
local origAutoRotate = true
local modButonlari = {}

local KOL_ADLARI = {
	["Left Shoulder"] = true,
	["Right Shoulder"] = true,
	["LeftShoulder"] = true,
	["RightShoulder"] = true,
}

local function getHumanoid()
	local k = oyuncu.Character
	return k and k:FindFirstChildOfClass("Humanoid")
end

local function getRoot()
	local k = oyuncu.Character
	return k and k:FindFirstChild("HumanoidRootPart")
end

-- =========================================================
-- ARAYÜZ YARDIMCILARI
-- =========================================================
local function yuvarla(nesne, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 6)
	c.Parent = nesne
end

local function etiketOlustur(parent, metin)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, 0, 0, 24)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.SourceSansBold
	l.TextSize = 18
	l.TextColor3 = YAZI
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = metin
	l.LayoutOrder = #parent:GetChildren()
	l.Parent = parent
	return l
end

local function butonOlustur(parent, metin, tikla)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, 0, 0, 34)
	b.BackgroundColor3 = PASIF
	b.Font = Enum.Font.SourceSansBold
	b.TextSize = 18
	b.TextColor3 = YAZI
	b.Text = metin
	b.LayoutOrder = #parent:GetChildren()
	yuvarla(b)
	b.Parent = parent
	if tikla then
		b.Activated:Connect(tikla)
	end
	return b
end

-- Sayı girişi. uygula(n) sınırlanmış değeri geri döndürmeli.
local function girdiOlustur(parent, metin, varsayilan, uygula)
	local satir = Instance.new("Frame")
	satir.Size = UDim2.new(1, 0, 0, 32)
	satir.BackgroundTransparency = 1
	satir.LayoutOrder = #parent:GetChildren()
	satir.Parent = parent

	local etiket = Instance.new("TextLabel")
	etiket.Size = UDim2.new(0.62, 0, 1, 0)
	etiket.BackgroundTransparency = 1
	etiket.Font = Enum.Font.SourceSans
	etiket.TextSize = 17
	etiket.TextColor3 = YAZI
	etiket.TextXAlignment = Enum.TextXAlignment.Left
	etiket.Text = metin
	etiket.Parent = satir

	local kutu = Instance.new("TextBox")
	kutu.Size = UDim2.new(0.36, 0, 1, 0)
	kutu.Position = UDim2.new(0.64, 0, 0, 0)
	kutu.BackgroundColor3 = KOYU
	kutu.Font = Enum.Font.SourceSansBold
	kutu.TextSize = 18
	kutu.TextColor3 = YAZI
	kutu.ClearTextOnFocus = false
	kutu.Text = tostring(varsayilan)
	yuvarla(kutu)
	kutu.Parent = satir

	local son = varsayilan
	kutu.FocusLost:Connect(function()
		local n = tonumber(kutu.Text)
		if n and n == n then
			son = uygula(n)
		end
		kutu.Text = tostring(son)
	end)

	local function ayarla(v)
		son = v
		kutu.Text = tostring(v)
	end
	return kutu, ayarla
end

-- Aç/kapat düğmesi. Geri dönen fonksiyonla durum dışarıdan değiştirilebilir.
local function anahtarOlustur(parent, metin, degisti)
	local durum = false
	local b
	local function guncelle()
		b.Text = metin .. (durum and ": AÇIK" or ": KAPALI")
		b.BackgroundColor3 = durum and AKTIF or PASIF
	end
	b = butonOlustur(parent, metin, function()
		durum = not durum
		guncelle()
		degisti(durum)
	end)
	guncelle()
	return function(v)
		durum = v
		guncelle()
	end
end

-- Mouse ve dokunmatik ile sürükleme. Sürüklenmeden tıklanırsa tiklandi() çalışır.
local function surukle(tutamac, hedefNesne, tiklandi)
	local suruklenior = false
	local hareketEtti = false
	local baslangic = Vector3.new(0, 0, 0)
	local baslangicKonum = hedefNesne.Position

	tutamac.InputBegan:Connect(function(girdi)
		if girdi.UserInputType == Enum.UserInputType.MouseButton1 or girdi.UserInputType == Enum.UserInputType.Touch then
			suruklenior = true
			hareketEtti = false
			baslangic = girdi.Position
			baslangicKonum = hedefNesne.Position
			girdi.Changed:Connect(function()
				if girdi.UserInputState == Enum.UserInputState.End then
					suruklenior = false
					if not hareketEtti and tiklandi then
						tiklandi()
					end
				end
			end)
		end
	end)

	UserInputService.InputChanged:Connect(function(girdi)
		if not suruklenior then
			return
		end
		if girdi.UserInputType == Enum.UserInputType.MouseMovement or girdi.UserInputType == Enum.UserInputType.Touch then
			local fark = girdi.Position - baslangic
			if fark.Magnitude > 6 then
				hareketEtti = true
			end
			if hareketEtti then
				hedefNesne.Position = UDim2.new(
					baslangicKonum.X.Scale,
					baslangicKonum.X.Offset + fark.X,
					baslangicKonum.Y.Scale,
					baslangicKonum.Y.Offset + fark.Y
				)
			end
		end
	end)
end

-- =========================================================
-- ARAYÜZ İSKELETİ
-- =========================================================
local gui = Instance.new("ScreenGui")
gui.Name = "OyunPaneli"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 50
gui.Parent = oyuncu:WaitForChild("PlayerGui")

local menu = Instance.new("Frame")
menu.Name = "Menu"
menu.Size = UDim2.new(0, 380, 0, 300)
menu.Position = UDim2.new(0.5, -190, 0.5, -150)
menu.BackgroundColor3 = ARKA
menu.BorderSizePixel = 0
menu.Active = true
menu.Visible = false
yuvarla(menu, 10)
menu.Parent = gui

local baslik = Instance.new("Frame")
baslik.Size = UDim2.new(1, -32, 0, 30)
baslik.BackgroundColor3 = KOYU
baslik.BorderSizePixel = 0
yuvarla(baslik, 8)
baslik.Parent = menu

local baslikYazi = Instance.new("TextLabel")
baslikYazi.Size = UDim2.new(1, -10, 1, 0)
baslikYazi.Position = UDim2.new(0, 10, 0, 0)
baslikYazi.BackgroundTransparency = 1
baslikYazi.Font = Enum.Font.SourceSansBold
baslikYazi.TextSize = 18
baslikYazi.TextColor3 = YAZI
baslikYazi.TextXAlignment = Enum.TextXAlignment.Left
baslikYazi.Text = "Panel (sürükle)"
baslikYazi.Parent = baslik

local kapat = Instance.new("TextButton")
kapat.Size = UDim2.new(0, 30, 0, 30)
kapat.Position = UDim2.new(1, -30, 0, 0)
kapat.BackgroundColor3 = Color3.fromRGB(190, 60, 60)
kapat.Font = Enum.Font.SourceSansBold
kapat.TextSize = 18
kapat.TextColor3 = YAZI
kapat.Text = "X"
yuvarla(kapat, 8)
kapat.Parent = menu
kapat.Activated:Connect(function()
	menu.Visible = false
end)

-- Sürüklenebilen kare tuş
local acKapaTus = Instance.new("TextButton")
acKapaTus.Name = "AcKapaTus"
acKapaTus.Size = UDim2.new(0, 50, 0, 50)
acKapaTus.Position = UDim2.new(0, 20, 0.5, -25)
acKapaTus.BackgroundColor3 = AKTIF
acKapaTus.Font = Enum.Font.SourceSansBold
acKapaTus.TextSize = 28
acKapaTus.TextColor3 = YAZI
acKapaTus.Text = "≡"
acKapaTus.Active = true
yuvarla(acKapaTus, 8)
acKapaTus.Parent = gui

surukle(acKapaTus, acKapaTus, function()
	menu.Visible = not menu.Visible
end)
surukle(baslik, menu, nil)

-- Sekmeler
local SEKME_ADLARI = { "Hareket", "Troll", "Oyuncular", "Karakter" }
local sayfalar = {}
local sekmeButonlari = {}

local sekmeCubugu = Instance.new("Frame")
sekmeCubugu.Size = UDim2.new(1, -10, 0, 30)
sekmeCubugu.Position = UDim2.new(0, 5, 0, 34)
sekmeCubugu.BackgroundTransparency = 1
sekmeCubugu.Parent = menu

local sekmeDizilim = Instance.new("UIListLayout")
sekmeDizilim.FillDirection = Enum.FillDirection.Horizontal
sekmeDizilim.Padding = UDim.new(0, 4)
sekmeDizilim.SortOrder = Enum.SortOrder.LayoutOrder
sekmeDizilim.Parent = sekmeCubugu

local function sayfaOlustur()
	local sf = Instance.new("ScrollingFrame")
	sf.Size = UDim2.new(1, -10, 1, -73)
	sf.Position = UDim2.new(0, 5, 0, 68)
	sf.BackgroundTransparency = 1
	sf.BorderSizePixel = 0
	sf.ScrollBarThickness = 4
	sf.AutomaticCanvasSize = Enum.AutomaticSize.Y
	sf.CanvasSize = UDim2.new(0, 0, 0, 0)
	sf.Visible = false
	sf.Parent = menu

	local dizilim = Instance.new("UIListLayout")
	dizilim.Padding = UDim.new(0, 6)
	dizilim.SortOrder = Enum.SortOrder.LayoutOrder
	dizilim.Parent = sf
	return sf
end

local function sekmeAc(ad)
	for isim, sayfa in pairs(sayfalar) do
		sayfa.Visible = (isim == ad)
	end
	for isim, b in pairs(sekmeButonlari) do
		b.BackgroundColor3 = (isim == ad) and AKTIF or PASIF
	end
end

for sira, ad in ipairs(SEKME_ADLARI) do
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0.25, -3, 1, 0)
	b.BackgroundColor3 = PASIF
	b.Font = Enum.Font.SourceSansBold
	b.TextSize = 17
	b.TextColor3 = YAZI
	b.Text = ad
	b.LayoutOrder = sira
	yuvarla(b)
	b.Parent = sekmeCubugu
	b.Activated:Connect(function()
		sekmeAc(ad)
	end)
	sekmeButonlari[ad] = b
	sayfalar[ad] = sayfaOlustur()
end

local hareketSayfa = sayfalar["Hareket"]
local trollSayfa = sayfalar["Troll"]
local oyuncuSayfa = sayfalar["Oyuncular"]
local karakterSayfa = sayfalar["Karakter"]

-- =========================================================
-- HEDEF / OYUNCU LİSTESİ MANTIĞI
-- =========================================================
local function hedefKok()
	if not hedef or not hedef.Parent then
		return nil
	end
	local k = hedef.Character
	return k and k:FindFirstChild("HumanoidRootPart")
end

local function hedefGuncelle()
	local metin = "Hedef: yok"
	if hedef then
		metin = "Hedef: " .. hedef.DisplayName
	end
	for _, l in ipairs(hedefEtiketleri) do
		l.Text = metin
	end
	for _, e in ipairs(oyuncuButonlari) do
		e.btn.BackgroundColor3 = (e.plr == hedef) and AKTIF or PASIF
	end
end

local function uyari(metin)
	for _, l in ipairs(hedefEtiketleri) do
		l.Text = metin
	end
	task.delay(2, hedefGuncelle)
end

local function oyunculariYenile()
	for _, e in ipairs(oyuncuButonlari) do
		e.btn:Destroy()
	end
	oyuncuButonlari = {}
	if hedef and not hedef.Parent then
		hedef = nil
	end
	for _, p in ipairs(Players:GetPlayers()) do
		local ad = p.DisplayName .. " (@" .. p.Name .. ")"
		if p == oyuncu then
			ad = ad .. " [Sen]"
		end
		local b = butonOlustur(oyuncuSayfa, ad, function()
			hedef = p
			hedefGuncelle()
		end)
		table.insert(oyuncuButonlari, { btn = b, plr = p })
	end
	hedefGuncelle()
end

-- =========================================================
-- TROLL (IŞINLANMA) FONKSİYONLARI
-- =========================================================
local function isinlanVeDon(onde)
	if mesgul then
		return
	end
	local kok = getRoot()
	local hk = hedefKok()
	if not kok or not hk then
		uyari("Önce Oyuncular sekmesinden hedef seç!")
		return
	end
	mesgul = true
	local eski = kok.CFrame
	local yon = onde and 1 or -1
	local poz = hk.Position + hk.CFrame.LookVector * (4 * yon)
	local bakis = Vector3.new(hk.Position.X, poz.Y, hk.Position.Z)
	kok.CFrame = CFrame.lookAt(poz, bakis)
	task.wait(1.5)
	if kok.Parent then
		kok.CFrame = eski
		kok.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	end
	mesgul = false
end

local function etrafindaDon()
	if mesgul then
		return
	end
	local kok = getRoot()
	if not kok or not hedefKok() then
		uyari("Önce Oyuncular sekmesinden hedef seç!")
		return
	end
	mesgul = true
	local eski = kok.CFrame
	local baslangicZamani = os.clock()
	while os.clock() - baslangicZamani < 5 do
		local hk = hedefKok()
		if not hk or not kok.Parent then
			break
		end
		local a = (os.clock() - baslangicZamani) * 8
		local poz = hk.Position + Vector3.new(math.cos(a) * 5, 0, math.sin(a) * 5)
		kok.CFrame = CFrame.lookAt(poz, hk.Position)
		kok.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		RunService.Heartbeat:Wait()
	end
	if kok.Parent then
		kok.CFrame = eski
		kok.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	end
	mesgul = false
end

-- =========================================================
-- KARAKTER (KORKU) MODLARI
-- =========================================================
local MODLAR = {
	{ id = "Titreme", ad = "Vücut Titremesi" },
	{ id = "Kafa", ad = "Kafa Çevirme" },
	{ id = "Kol", ad = "Kol Sallama" },
	{ id = "Suzul", ad = "Hayalet Süzülme" },
	{ id = "Don", ad = "Hızlı Dönme" },
}

local function modButonlariGuncelle()
	for id, b in pairs(modButonlari) do
		b.BackgroundColor3 = (id == aktifMod) and AKTIF or PASIF
	end
end

local function motorlariTopla()
	local liste = {}
	local k = oyuncu.Character
	if k then
		for _, d in ipairs(k:GetDescendants()) do
			if d:IsA("Motor6D") then
				table.insert(liste, d)
			end
		end
	end
	return liste
end

local function modTemizle()
	for m, c0 in pairs(origC0) do
		if m.Parent then
			m.C0 = c0
		end
	end
	origC0 = {}
	local hum = getHumanoid()
	if hum then
		hum.HipHeight = origHip
		hum.AutoRotate = origAutoRotate
	end
end

local function modDegistir(isim)
	local onceki = aktifMod
	if onceki then
		modTemizle()
		aktifMod = nil
	end
	if isim and onceki ~= isim then
		local hum = getHumanoid()
		if hum then
			aktifMod = isim
			modZaman = 0
			modSayac = 0
			origHip = hum.HipHeight
			origAutoRotate = hum.AutoRotate
			origC0 = {}
			for _, m in ipairs(motorlariTopla()) do
				if m.Name ~= "Root" and m.Name ~= "RootJoint" then
					origC0[m] = m.C0
				end
			end
			if isim == "Don" then
				hum.AutoRotate = false
			end
		end
	end
	modButonlariGuncelle()
end

local function modUygula(dt, hum, kok)
	modZaman += dt
	if aktifMod == "Titreme" then
		modSayac += dt
		if modSayac >= 0.05 then
			modSayac = 0
			for m, c0 in pairs(origC0) do
				if m.Parent then
					m.C0 = c0 * CFrame.Angles(rnd:NextNumber(-0.4, 0.4), rnd:NextNumber(-0.4, 0.4), rnd:NextNumber(-0.4, 0.4))
				end
			end
		end
	elseif aktifMod == "Kafa" then
		modSayac += dt
		if modSayac >= 0.7 then
			modSayac = 0
			for m, c0 in pairs(origC0) do
				if m.Parent and m.Name == "Neck" then
					m.C0 = c0 * CFrame.Angles(rnd:NextNumber(-0.5, 0.5), rnd:NextNumber(-2, 2), rnd:NextNumber(-1, 1))
				end
			end
		end
	elseif aktifMod == "Kol" then
		local a = math.sin(modZaman * 14) * 1.3
		for m, c0 in pairs(origC0) do
			if m.Parent and KOL_ADLARI[m.Name] then
				local sol = string.find(m.Name, "Left") ~= nil
				local aci = a
				if sol then
					aci = -a
				end
				m.C0 = c0 * CFrame.Angles(0, 0, aci)
			end
		end
	elseif aktifMod == "Suzul" then
		hum.HipHeight = origHip + 2 + math.sin(modZaman * 2) * 0.6
	elseif aktifMod == "Don" then
		kok.CFrame = kok.CFrame * CFrame.Angles(0, dt * 14, 0)
	end
end

-- =========================================================
-- SEKME: HAREKET
-- =========================================================
local _, setHiz = girdiOlustur(hareketSayfa, "Hız (WalkSpeed)", 16, function(n)
	n = math.clamp(n, 0, 500)
	ayar.HizDeger = n
	return n
end)

local _, setZipla = girdiOlustur(hareketSayfa, "Zıplama Gücü", 50, function(n)
	n = math.clamp(n, 0, 500)
	ayar.ZiplamaDeger = n
	return n
end)

local _, setGrav = girdiOlustur(hareketSayfa, "Gravity (Yerçekimi)", math.floor(VARSAYILAN_YERCEKIMI * 10) / 10, function(n)
	n = math.clamp(n, 0, 1000)
	ayar.YercekimiDeger = n
	Workspace.Gravity = n
	return n
end)

local _, setDusme = girdiOlustur(hareketSayfa, "Düşme Hızı Limiti (0=kapalı)", 0, function(n)
	n = math.clamp(n, 0, 1000)
	ayar.DusmeLimiti = n
	return n
end)

local setZigzag = anahtarOlustur(hareketSayfa, "Yan Yan Hızlı Yürüme", function(acik)
	ayar.Zigzag = acik
end)

local _, setZigGenislik = girdiOlustur(hareketSayfa, "Zigzag Genişlik", 2, function(n)
	n = math.clamp(n, 0, 10)
	ayar.ZigzagGenislik = n
	return n
end)

local _, setZigSiklik = girdiOlustur(hareketSayfa, "Zigzag Sıklık", 20, function(n)
	n = math.clamp(n, 1, 100)
	ayar.ZigzagSiklik = n
	return n
end)

butonOlustur(hareketSayfa, "Hepsini Sıfırla", function()
	ayar.HizDeger = nil
	ayar.ZiplamaDeger = nil
	ayar.YercekimiDeger = nil
	ayar.DusmeLimiti = 0
	ayar.Zigzag = false
	ayar.ZigzagGenislik = 2
	ayar.ZigzagSiklik = 20
	Workspace.Gravity = VARSAYILAN_YERCEKIMI
	local hum = getHumanoid()
	if hum then
		hum.WalkSpeed = 16
		hum.UseJumpPower = true
		hum.JumpPower = 50
	end
	setHiz(16)
	setZipla(50)
	setGrav(math.floor(VARSAYILAN_YERCEKIMI * 10) / 10)
	setDusme(0)
	setZigzag(false)
	setZigGenislik(2)
	setZigSiklik(20)
end)

-- =========================================================
-- SEKME: TROLL
-- =========================================================
table.insert(hedefEtiketleri, etiketOlustur(trollSayfa, "Hedef: yok"))

butonOlustur(trollSayfa, "Önüne Işınlan ve Geri Dön", function()
	task.spawn(isinlanVeDon, true)
end)

butonOlustur(trollSayfa, "Arkasına Işınlan ve Geri Dön", function()
	task.spawn(isinlanVeDon, false)
end)

butonOlustur(trollSayfa, "Etrafında Dön (5 sn) ve Geri Dön", function()
	task.spawn(etrafindaDon)
end)

anahtarOlustur(trollSayfa, "Hedefin Arkasına Yapış (Takip)", function(acik)
	takipAcik = acik
end)

-- =========================================================
-- SEKME: OYUNCULAR
-- =========================================================
butonOlustur(oyuncuSayfa, "Oyuncuları Yenile", oyunculariYenile)
table.insert(hedefEtiketleri, etiketOlustur(oyuncuSayfa, "Hedef: yok"))

-- =========================================================
-- SEKME: KARAKTER
-- =========================================================
etiketOlustur(karakterSayfa, "Bir mod seç (tekrar basınca kapanır)")

for _, m in ipairs(MODLAR) do
	modButonlari[m.id] = butonOlustur(karakterSayfa, m.ad, function()
		modDegistir(m.id)
	end)
end

butonOlustur(karakterSayfa, "Hepsini Kapat", function()
	modDegistir(nil)
end)

-- =========================================================
-- ANA DÖNGÜ
-- =========================================================
RunService.Heartbeat:Connect(function(dt)
	if ayar.YercekimiDeger then
		Workspace.Gravity = ayar.YercekimiDeger
	end

	local hum = getHumanoid()
	local kok = getRoot()
	if not hum or not kok then
		return
	end

	if ayar.HizDeger then
		hum.WalkSpeed = ayar.HizDeger
	end
	if ayar.ZiplamaDeger then
		hum.UseJumpPower = true
		hum.JumpPower = ayar.ZiplamaDeger
	end

	-- Düşme hızı limiti
	if ayar.DusmeLimiti > 0 then
		local v = kok.AssemblyLinearVelocity
		if v.Y < -ayar.DusmeLimiti then
			kok.AssemblyLinearVelocity = Vector3.new(v.X, -ayar.DusmeLimiti, v.Z)
		end
	end

	-- Yan yan hızlı yürüme: gittiğin yöne ilerlerken sağa sola titreşir
	local yon = hum.MoveDirection
	if ayar.Zigzag and yon.Magnitude > 0.1 then
		local yan = Vector3.new(-yon.Z, 0, yon.X)
		zigzagYon = yan
		zigzagFaz += dt * ayar.ZigzagSiklik
		local ofset = math.sin(zigzagFaz) * ayar.ZigzagGenislik
		kok.CFrame = kok.CFrame + yan * (ofset - zigzagOnceki)
		zigzagOnceki = ofset
	else
		if zigzagOnceki ~= 0 then
			kok.CFrame = kok.CFrame - zigzagYon * zigzagOnceki
			zigzagOnceki = 0
		end
		zigzagFaz = 0
	end

	-- Hedefin arkasına yapışma
	if takipAcik then
		local hk = hedefKok()
		if hk then
			kok.CFrame = hk.CFrame * CFrame.new(0, 0, 3)
			kok.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		end
	end

	-- Karakter korku modları
	if aktifMod then
		modUygula(dt, hum, kok)
	end
end)

-- =========================================================
-- OLAYLAR VE BAŞLANGIÇ
-- =========================================================
oyuncu.CharacterAdded:Connect(function()
	aktifMod = nil
	origC0 = {}
	zigzagOnceki = 0
	zigzagFaz = 0
	mesgul = false
	modButonlariGuncelle()
end)

Players.PlayerAdded:Connect(function()
	task.delay(0.2, oyunculariYenile)
end)

Players.PlayerRemoving:Connect(function(p)
	if p == hedef then
		hedef = nil
	end
	task.delay(0.2, oyunculariYenile)
end)

sekmeAc("Hareket")
oyunculariYenile()
