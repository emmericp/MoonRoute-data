
-- quick & dirty lua script to generate pgfplots data
-- sorry, no gnuplot for this one

-- copied from moongen stats.lua
function percentile(data, p)
	local sortedData = { }
	for k, v in ipairs(data) do
		sortedData[k] = v
	end
	table.sort(sortedData)
	-- (math.max to support getting the minimum via the 0th percentile)
	return sortedData[math.max(1, math.ceil(#sortedData * p / 100))]
end
function average(data)
	local sum = 0
	for i, v in ipairs(data) do
		sum = sum + v
	end
	return sum / #data
end
function standardDeviation(data)
	local avg = average(data)
	local sum = 0
	for i, v in ipairs(data) do
		sum = sum + (v - avg) ^ 2
	end
	return (sum / (#data - 1)) ^ 0.5
end


local p25, p50, p75, p99, pmax, pmin, avg, stdDev = {}, {}, {}, {}, {}, {}, {}, {}

-- usage: analyse.lua input_*_output_8_*
for i, f in ipairs{...} do
	print("parsing " .. f)
	f = io.open(f, "r")
	local data = {}
	for line in f:lines() do
		local bin, v = line:match("([^,]+),(.+)")
		bin, v = tonumber(bin), tonumber(v)
		for i = 1, v do
			table.insert(data, bin)
		end
	end
	-- ugly!
	table.insert(p25, percentile(data, 25))
	table.insert(p50, percentile(data, 50))
	table.insert(p75, percentile(data, 75))
	table.insert(p99, percentile(data, 99))
	table.insert(pmin, percentile(data, 0))
	table.insert(pmax, percentile(data, 100))
	table.insert(avg, average(data))
	table.insert(stdDev, standardDeviation(data))
end

local function printPgfPlotsData(data, color, style)
	print("\\addplot[mark=none,color=" .. color .. "," .. style .. "] coordinates {")
	for i, v in ipairs(data) do
		print(("(%d, %f)"):format(2^(i-1), v / 1000)) -- microseconds
	end
	print("};")
end

printPgfPlotsData(pmin, "gray", "dashed, thick")
--printPgfPlotsData(p25, "gray", "dashed, thick")
printPgfPlotsData(p50, "gray", "dashed, thick")
--printPgfPlotsData(p75, "gray", "dashed, thick")
--printPgfPlotsData(p99, "gray", "dashed, thick")
printPgfPlotsData(pmax, "gray", "dashed, thick")
