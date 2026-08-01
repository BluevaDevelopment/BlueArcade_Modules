-- Mirrors the business-logic half of legacy StructureService.java (pick order/shuffle/size
-- filter) - loading, pasting, and evaluating voxel data is session.structure's job instead.
local M = {}

local function reshuffle(state)
  state.structurePickOrder = {}
  for i = 1, #state.structures do
    state.structurePickOrder[i] = i
  end
  for i = #state.structurePickOrder, 2, -1 do
    local j = math.random(i)
    state.structurePickOrder[i], state.structurePickOrder[j] = state.structurePickOrder[j], state.structurePickOrder[i]
  end
  state.structurePickIndex = 1
end
M.reshuffle = reshuffle

function M.load(session, state)
  state.structures = session.structure.list()
  reshuffle(state)
end

function M.hasStructures(state)
  return #state.structures > 0
end

function M.filterByMaxSize(state, maxWidth, maxHeight, maxLength)
  local filtered = {}
  for _, structure in ipairs(state.structures) do
    if structure.width <= maxWidth and structure.height <= maxHeight and structure.length <= maxLength then
      filtered[#filtered + 1] = structure
    end
  end
  state.structures = filtered
  reshuffle(state)
end

function M.pickNext(state)
  if #state.structures == 0 then
    return nil
  end
  if #state.structures == 1 then
    return state.structures[1]
  end
  if #state.structurePickOrder ~= #state.structures or state.structurePickIndex > #state.structurePickOrder then
    reshuffle(state)
  end
  local index = state.structurePickOrder[state.structurePickIndex]
  state.structurePickIndex = state.structurePickIndex + 1
  return state.structures[index]
end

return M
