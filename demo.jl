using ray_core_worker_julia_jll: initialize_coreworker, shutdown_coreworker, put, get

initialize_coreworker()
obj_id = put("Greetings from Julia!")
result = get(obj_id)
shutdown_coreworker()

@show result
