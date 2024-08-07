--!NEEDS:ui/uipanel.lua
--!NEEDS:ui/uiaccordion.lua

AUI=AUI or {}
AUI.AssetItem=Core.class(UI.Panel,function(lib) end)
AUI.AssetItem.Template={
	class="AUI.AssetItem", 
	layoutModel={ cellSpacingY="aui_asitem.szSpacing", columnWeights={1}, rowWeights={1,0}, },
	children={
		{ class="UI.Image", name="img", layout={gridy=0, fill=Sprite.LAYOUT_FILL_BOTH } },
		{ class="UI.Label", name="lbl", layout={gridy=1, fill=Sprite.LAYOUT_FILL_BOTH }, 
			Font="aui_asitem.font",
			TextLayout = { flags = FontBase.TLF_REF_LINETOP | FontBase.TLF_VCENTER | FontBase.TLF_CENTER | FontBase.TLF_BREAKWORDS | FontBase.TLF_SINGLELINE },
		},
	}
}	

function AUI.AssetItem:init()
	UI.BuilderSelf(AUI.AssetItem.Template,self)
end

function AUI.AssetItem:setItem(name,texture)
	self.img:setImage(texture)
	self.lbl:setText(name)
end

AUI.AssetShelf=Core.class(UI.Panel,function(lib) end)
function AUI.AssetShelf:init(lib)
	self.lib=lib
	self.names=self.lib:getNames()
	local cols=5
	local rows=(#self.names+cols-1)//cols
	local cs="aui_asshelf.szColumn"
	local cw={}
	local rh={}
	for i=1,cols do cw[i]=cs end
	for i=1,rows do rh[i]=cs end
	self:setLayoutParameters({
		columnWidths=cw,
		cellSpacingX="aui_asshelf.szSpacing",
		cellSpacingY="aui_asshelf.szSpacing",
		rowHeights=rh,
	})
	local tpl=AUI.AssetItem.new()
	
	for ni,nn in ipairs(self.names) do
		local im=self.lib:getThumbnail(nn)
		local uim=tpl:clone()
		uim:setItem(nn,im)
		uim:setLayoutConstraints({
				gridx=(ni-1)%cols,
				gridy=(ni-1)//cols,
				fill=1, width=cs, height=cs,
			})
		uim.assetItemInfo={ lib=self.lib, name=nn }
		self:addChild(uim)
	end
		
	UI.Dnd.Source(self,true)
end

function AUI.AssetShelf:getDndData(x,y)
    x,y=self:localToGlobal(x,y)
    local eb=self:getChildrenAtPoint(x,y,true,true)
	for _,aim in ipairs(eb) do
		if aim.assetItemInfo then
			local marker=UI.Dnd.MakeMarker(aim.img)
			return { type=AUI.AssetItem, value=aim.assetItemInfo, visual=marker }
		end
	end

end

function AUI.AssetShelf:cleanupDndData(data,target)

end


AUI.AssetShelfLabel=Core.class(UI.Panel,function (item) return end)

AUI.AssetShelfLabel.Template={
	class="AUI.AssetShelfLabel", 
	LocalStyle="aui_aslib.styLabel",
	layoutModel={ insets="aui_asitem.szSpacing", cellSpacingX="aui_asitem.szSpacing", columnWeights={0,1,0}, rowWeights={1}, },
	children={
		{ class="UI.Image", Image="aui_aslib.icBRight", name="icn", layout={gridx=0, fill=Sprite.LAYOUT_FILL_BOTH, width="1em", height="1em" } },
		{ class="UI.Label", name="lbl", layout={gridx=1, fill=Sprite.LAYOUT_FILL_BOTH }, 
			TextLayout = { flags = FontBase.TLF_REF_LINETOP | FontBase.TLF_VCENTER | FontBase.TLF_LEFT | FontBase.TLF_SINGLELINE },
		},
		{ class="UI.Image", Image="aui_aslib.icTrash", name="btDelete", behavior=UI.Behavior.Button, layout={gridx=2, fill=Sprite.LAYOUT_FILL_BOTH, width="1em", height="1em" } },
	}
}	

function AUI.AssetShelfLabel:init(item)
	UI.BuilderSelf(AUI.AssetShelfLabel.Template,self)
	--self.img:setImage(item.assetLib:getThumbnail(item.assetName))		
	self.lbl:setText(item.name)
	self.name=item.name
end

function AUI.AssetShelfLabel:setFlags(changes)
	UI.Panel.setFlags(self,changes)
	if changes.expanded~=nil then
		self.icn:setImage(if changes.expanded then "aui_aslib.icBDown" else "aui_aslib.icBRight")
	end
end

function AUI.AssetShelfLabel:onWidgetAction(w)
	if w==self.btDelete then
		UI.dispatchEvent(self,"AssetShelfDelete",self.name)
	end
end

AUI.AssetLibrary=Core.class(UI.Accordion,function() end)
local function shelfBuilder(shelf,inside)
	if not inside then
		return AUI.AssetShelfLabel.new(shelf)
	else
		return AUI.AssetShelf.new(shelf)
	end
end

function AUI.AssetLibrary:updateLibrary(lib)
	self:setData(lib,shelfBuilder)
end
