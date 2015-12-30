require 'optim'
TrainingHelpers = {}

function TrainingHelpers.inspectLayer(layer, fields)
   function inspect(x)
      if x then
         x = x:double():view(-1)
         return {
            p5 = (x:kthvalue(1 + 0.05*x:size(1))[1]),
            mean = x:mean(),
            p95 = (x:kthvalue(1 + 0.95*x:size(1))[1]),
            var = x:var(),
         }
      end
   end
   local result = {name = tostring(layer)}
   for _,field in ipairs(fields) do
      result[field] = inspect(layer[field])
   end
   return result
end
function TrainingHelpers.printLayerInspection(li, fields)
   print("- "..tostring(li.name))
   if (string.find(tostring(li.name), "ReLU")
       or string.find(tostring(li.name), "BatchNorm")
       or string.find(tostring(li.name), "View")
       ) then
       -- Do not print these layers
   else
       for _,field in ipairs(fields) do
          local lf = li[field]
          if lf then
              print(string.format(
                       "%20s    5p: %+3e    Mean: %+3e    95p: %+3e    Var: %+3e",
                       field, lf.p5, lf.mean, lf.p95, lf.var))
          end
       end
   end
end
function TrainingHelpers.inspectModel(model)
   local results = {}
   for i,layer in ipairs(model.modules) do
      results[i] = TrainingHelpers.inspectLayer(layer, {"weight",
                                                        "gradWeight",
                                                        "bias",
                                                        "gradBias",
                                                        "output"})
   end
   return results
end
function TrainingHelpers.printInspection(inspection)
   print("\n\n\n")
   print(" \x1b[31m---------------------- Weights ---------------------- \x1b[0m")
   for i,layer in ipairs(inspection) do
      TrainingHelpers.printLayerInspection(layer, {"weight", "gradWeight"})
   end
   print(" \x1b[31m---------------------- Biases ---------------------- \x1b[0m")
   for i,layer in ipairs(inspection) do
      TrainingHelpers.printLayerInspection(layer, {"bias", "gradBias"})
   end
   print(" \x1b[31m---------------------- Outputs ---------------------- \x1b[0m")
   for i,layer in ipairs(inspection) do
      TrainingHelpers.printLayerInspection(layer, {"output"})
   end
end


function TrainingHelpers.trainForever(model, forwardBackwardBatch, weights, sgdState, sampler, epochSize, afterEpoch, filename)
   local modelTag = torch.random()
   sgdState.epochSize = epochSize
   if sgdState.epochCounter == nil then
      sgdState.epochCounter = 0
   end
   if sgdState.nSampledImages == nil then
     sgdState.nSampledImages = 0
   end
   if sgdState.nEvalCounter == nil then
      sgdState.nEvalCounter = 0
   end
   if sgdState.lossLog == nil then
       sgdState.lossLog = {}
   end
   if sgdState.inspectionLog == nil then
       sgdState.inspectionLog = {}
   end
   local whichOptimMethod = optim.sgd
   if sgdState.whichOptimMethod then
       whichOptimMethod = optim[sgdState.whichOptimMethod]
   end
   while true do -- Each epoch
      collectgarbage(); collectgarbage()
      batch = sampler()
      if not batch then
         break
      end
      -- Run forward and backward pass on inputs and labels
      model:training()
      local loss_val, gradients = forwardBackwardBatch(batch)
      -- SGD step: modifies weights in-place
      whichOptimMethod(function() return loss_val, gradients end,
                       weights,
                       sgdState)
      -- Display progress and loss
      sgdState.nSampledImages = sgdState.nSampledImages + batch.inputs:size(1)
      sgdState.nEvalCounter = sgdState.nEvalCounter + 1
      xlua.progress(sgdState.nSampledImages%epochSize, epochSize)
      if sgdState.nEvalCounter % 20 == 0 then
          print("\027[KLoss:", loss_val)
      end
      -- if sgdState.nEvalCounter % 100 == 0 then
      --     local inspection = TrainingHelpers.inspectModel(model)
      --     inspection.nSampledImages = sgdState.nSampledImages
      --     table.insert(sgdState.inspectionLog, inspection)
      -- end
      table.insert(sgdState.lossLog, {loss = loss_val, nSampledImages = sgdState.nSampledImages})
      if math.floor(sgdState.nSampledImages / epochSize) ~= sgdState.epochCounter then
         -- Epoch completed!
         sgdState.epochCounter = math.floor(sgdState.nSampledImages / epochSize)
         if afterEpoch then afterEpoch() end

         print("\n\n----- Epoch "..sgdState.epochCounter.." -----")
         -- Every so often, decrease learning rate
         if sgdState.epochCounter % sgdState.epochDropCount == 0 then
            sgdState.learningRate = sgdState.learningRate * 0.1
            print("Dropped learning rate to", sgdState.learningRate)
         end
         -- Snapshot model (WARNING: Should be the last thing we do!)
         if filename then
            local newFilename = filename.."-"..modelTag
            --print("Snapshotting model to "..newFilename)
            --torch.save(newFilename.."-model.tmp", model)
            --os.rename(newFilename.."-model.tmp", newFilename.."-model.t7") -- POSIX guarantees automicity
            print("Snapshotting sgdState to "..newFilename)
            torch.save(newFilename.."-sgdState.tmp", sgdState)
            os.rename(newFilename.."-sgdState.tmp", newFilename.."-sgdState.t7") -- POSIX guarantees automicity
         end
      end
   end
end