using Random
using Images

include("../../configs.jl")

mutable struct Image_Reader
    augment::Bool
    pre_scales::Array{Float64}
    function Image_Reader(augment::Bool=false)
        crop_ratios = [0.6, 0.8, 1.0]
        return new(augment, crop_ratios)
    end
end

# r is the reader object
function read_img(dir; len=nothing, boxes=nothing, r=nothing)
    
    img = convert(Array{Int64}, rawview(channelview(load(dir))))
    new_boxes = boxes === nothing ? nothing : deepcopy(boxes)
    c, h, w = size(img)
    
    if len === nothing
        len = max(w, h) # makes image square without changing its size, for evaluation
        div = Int(ceil(len / 64))
        len = 64 * div
    end
    
    if r !== nothing && r.augment 
        img = convert(Array{Float32}, img) ./ 255
        roi = _find_roi(r, img)
        # horizontal flip
        if rand() < 0.5 img, new_boxes = flip_horizontal(img, new_boxes) end
        # color distortion
        img = distort_color(img)
        # cropping the picture with a scale
        img, new_boxes = crop_image(img, new_boxes, roi)
        # resizing to <len>
        img, new_boxes = resize_square_img(img, new_boxes, len, (roi[3] - roi[1]))
        img .*= 255
    else
        img = convert(Array{Float32}, img) ./ 255
        img = squaritize_img(img, len)
        # img, new_boxes = resize_square_img(img, new_boxes, len, maxlen) 
        img .*= 255
    end 
            
    if new_boxes !== nothing 
        new_boxes[new_boxes .< 0] .= -1
        bbox_indices = getindex.(findall(new_boxes[1,:] .>= 0)) # images having bboxes
        new_boxes = new_boxes[:,bbox_indices]  
    end
    
    img .-= avg_img 
    return img, new_boxes
end

function _find_roi(r::Image_Reader, img)
    c, h, w = size(img)
    maxlen = max(h, w); minlen = min(h, w)
    scale = r.pre_scales[rand(1:length(r.pre_scales))]
    new_short = Int(ceil(minlen * scale))
    x1 = 1; y1 = 1
    if scale < 1
        x1 = rand(1:max(1, w-new_short))
        y1 = rand(1:max(1, h-new_short))
    end
    x2 = (new_short-1) + x1
    y2 = (new_short-1) + y1
    #region of interest is determined
    return [x1 y1 x2 y2] 
end

function crop_image(img, new_boxes, roi)
    img = img[:, roi[2]:roi[4], roi[1]:roi[3]]
    box_size = size(new_boxes)

    for person in 1:box_size[2]
        # setting landmarks outside of the region to -1
        for lm in 5:2:box_size[1]-2
            # if not in the cropped area
            if (new_boxes[lm, person] > roi[3]) || 
                (new_boxes[lm, person] < roi[1]) || 
                (new_boxes[lm + 1, person] > roi[4]) || 
                (new_boxes[lm + 1, person] < roi[2])
                new_boxes[lm, person] = -1
                new_boxes[lm + 1, person] = -1
            # if in the cropped area
            else
                new_boxes[lm, person] -= roi[1]
                new_boxes[lm + 1, person] -= roi[2]
            end
        end
        if !all(>=(0), new_boxes[5:14,person])
            new_boxes[15, person] = -1.0
        end
        # setting bounding box coordinates
        
        # completely off the cropped area
        if (new_boxes[3,person] <= roi[1]) || (new_boxes[1,person] >= roi[3]) 
            new_boxes[1:4, person] .= -1
        elseif (new_boxes[4,person] <= roi[2]) || (new_boxes[2,person] >= roi[4])
            new_boxes[1:4, person] .= -1
        else
            # partial fits
            if new_boxes[3,person] > roi[3]
                new_boxes[3,person] = roi[3]
            end 
            if new_boxes[4,person] > roi[4]
                new_boxes[4,person] = roi[4]
            end  
            
            if 0 <= new_boxes[1,person] && new_boxes[1,person] < roi[1]
                new_boxes[1,person] = 0
            else
                new_boxes[1,person] -= roi[1]
            end 
            new_boxes[3,person] -= roi[1]
            
            if 0 <= new_boxes[2,person] && new_boxes[2,person] < roi[2]
                new_boxes[2,person] = 0
            else
                new_boxes[2,person] -= roi[2]
            end
            new_boxes[4,person] -= roi[2]
        end
    end
    
    return img, new_boxes
end

function resize_square_img(img, new_boxes, new_len, old_len)
    img = imresize(img, (3, new_len, new_len))
    ratio = new_len / old_len
    if new_boxes !== nothing
        new_boxes = ratio .* new_boxes
    end
    return img, new_boxes
end

function squaritize_img(img, len)
    c, h, w = size(img)
    full_img = zeros(3, len, len)
    full_img[:,1:h,1:w] .= img
    return full_img
end

function flip_horizontal(img, new_boxes)
    img = reverse(img, dims=3)
    new_boxes[1:2:13,:] .= size(img, 3) .- new_boxes[1:2:13,:]
    temp = new_boxes[3,:]
    new_boxes[3,:] .= new_boxes[1,:]
    new_boxes[1,:] .= temp
    new_boxes[new_boxes .> size(img, 3)] .= -1
    return img, new_boxes
end

function distort_color(img)
    # brightness distortion
    if rand() < 0.5 img = _convert(img, beta=rand(-0.125:0.125)) end 
    # contrast distortion
    if rand() < 0.5 img = _convert(img, alpha=rand(0.5:1.5)) end
    
    img = channelview(colorview(HSV, float.(img)))
    # saturation distortion
    if rand() < 0.5 img[2,:,:] = _convert(img[2,:,:], alpha=rand(0.5:1.5)) end
    # hue distortion
    if rand() < 0.5 img[1,:,:] = _convert(img[1,:,:], beta=rand(-(18/256):(18/256))) end
    
    img = channelview(colorview(RGB, colorview(HSV, img)))
    return img
end

function _convert(image; alpha=1, beta=0)
    image = image .* alpha .+ beta
    image[image .< 0] .= 0
    image[image .> 1] .= 1
    return image
end