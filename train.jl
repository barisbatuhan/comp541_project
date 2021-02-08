using ArgParse

include("BBTNet/model/retinaface.jl")
include("BBTNet/datasets/WIDERFACE.jl")
include("configs.jl")
include("./DeepJulia/DeepJulia.jl")

function parse_cmd()
    s = ArgParseSettings(commands_are_required = false)
    @add_arg_table s begin
        "--batch_size", "-b"
            help = "Batch size to take for training."
            arg_type = Int
            default = 10
            required = false
        "--load_dir"
            help = "If there is a pretrained model, then the path of it."
            arg_type = String
            default = nothing
            required = false
        "--save_dir", "-s"
            help = "Directory path for saving a model after each epoch."
            arg_type = String
            default = "./weights/"
            required = false
        "--log_file"
            help = "Log file directory to write losses after each batch evaluation."
            arg_type = String
            default = nothing
            required = false
        "--backbone"
            help = "Backbone to use. 2 options are available: \"resnet50\" and \"mobilenet\"."
            arg_type = String
            default = "resnet50"
            required = false
        "--mode", "-m"
            help = "Training mode: 0 for only baseline, 1 for full model, 2 for no cascaded structure."
            arg_type = Int
            default = 1
            required = false
        "--use_context"
            help = "0 for not using any context module, others for using it."
            arg_type = Int
            default = 1
            required = false
        "--laterals", "-l"
            help = "How many lateral connections will be processed, either 3 or 5. 5 is needed for full model."
            arg_type = Int
            default = 5
            required = false
        "--start_epoch", "-e"
            help = "From which epoch the training will continue."
            arg_type = Int
            default = 1
            required = false
    end  
    return parse_args(s) 
end

function main()
    parsed_args = parse_cmd()
    mode = parsed_args["mode"]
    scale_cnt = parsed_args["laterals"]
    num_anchors = scale_cnt == 3 ? 2 : 3
    anchor_info = scale_cnt == 3 ? lat_3_anchors : lat_5_anchors

    use_context = parsed_args["use_context"] == 0 ? false : true
    backbone = parsed_args["backbone"]

    if backbone != "resnet50" && backbone != "mobilenet"
        println("[ERROR] An undefined backbone is added!")
        return nothing
    end
    
    bs = parsed_args["batch_size"]
    start_epoch = parsed_args["start_epoch"]
    load_path = parsed_args["load_dir"]; save_path = parsed_args["save_dir"]; log_path = parsed_args["log_file"];
    
    train_dir = wf_path * "train/"
    labels_dir = wf_labels_path * "train/"
    data = WIDER_Data(train_dir, labels_dir, train=true, shuffle=true, batch_size=bs)
    print("[INFO] Data is loaded!\n")
    
    model = RetinaFace(
        mode=mode, num_anchors=num_anchors, anchor_info=anchor_info, 
        load_path=load_path, include_context_module=use_context,
    )
    model = set_train_mode(model)
    if run_gpu 
        model = to_gpu(model)
    end
    print("[INFO] Model is loaded!\n")
    
    train_model(model, data, save_dir=save_path, start_epoch=start_epoch, log_file=log_path)
end

main()
