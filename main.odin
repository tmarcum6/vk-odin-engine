package main

import "core:fmt"
import "core:os"
import "core:strings"
import "vendor:glfw"
import vk "vendor:vulkan"

byte_arr_str :: proc(arr: ^[$N]byte) -> string {
	return strings.truncate_to_byte(string(arr[:]), 0)
}

Platform_Info :: struct {
	required_extensions: []cstring,
	surface_creation:    proc(
		instance: vk.Instance,
		window: glfw.WindowHandle,
	) -> (
		vk.Result,
		vk.SurfaceKHR,
	),
}

VulkanContext :: struct {
	instance:              vk.Instance,
	gpu:                   vk.PhysicalDevice,
	surface:               vk.SurfaceKHR,
	queue_family_index:    u32,
	device:                vk.Device,
	swapchain:             vk.SwapchainKHR,
	render_pass:           vk.RenderPass,
	framebuffers:          []vk.Framebuffer,
	command_pool:          vk.CommandPool,
	command_buffers:       []vk.CommandBuffer,
	graphics_queue:        vk.Queue,
	swapchain_images:      []vk.Image,
	swapchain_image_views: []vk.ImageView,
	chosen_format:         vk.SurfaceFormatKHR,
	swapchain_extent:      vk.Extent2D,
}

AppRunner :: struct {
	window:             glfw.WindowHandle,
	vulkan:             VulkanContext,
	platform:           Platform_Info,
	acquired_semaphore: vk.Semaphore,
}

get_platform_info :: proc() -> Platform_Info {
	exts := glfw.GetRequiredInstanceExtensions()

	create_surface :: proc(
		instance: vk.Instance,
		window: glfw.WindowHandle,
	) -> (
		vk.Result,
		vk.SurfaceKHR,
	) {
		fmt.println("creating surface...")
		surface: vk.SurfaceKHR
		result := glfw.CreateWindowSurface(instance, window, nil, &surface)
		fmt.println("surface created:", result)
		return result, surface
	}

	return Platform_Info{required_extensions = exts, surface_creation = create_surface}
}

init_vulkan_context :: proc(app: ^AppRunner) -> bool {
	fmt.println("init_vulkan_context start")
	platform := &app.platform
	vulkan := &app.vulkan
	window := app.window

	create_info := vk.InstanceCreateInfo {
		sType            = vk.StructureType.INSTANCE_CREATE_INFO,
		pApplicationInfo = &vk.ApplicationInfo {
			sType = vk.StructureType.APPLICATION_INFO,
			pApplicationName = "Test Engine",
			applicationVersion = vk.MAKE_VERSION(1, 0, 0),
			apiVersion = vk.API_VERSION_1_0,
		},
	}

	create_info.enabledExtensionCount = u32(len(platform.required_extensions))
	create_info.ppEnabledExtensionNames = raw_data(platform.required_extensions)
	fmt.println("about to create instance...")

	result := vk.CreateInstance(&create_info, nil, &vulkan.instance)
	if result != vk.Result.SUCCESS {
		fmt.println("failed to enumerate vulkan instance version", result)
		return false
	}

	result = vk.CreateInstance(&create_info, nil, &vulkan.instance)
	if result != vk.Result.SUCCESS {
		fmt.println("failed to create vulkan instance", result)
		return false
	}
	fmt.println("instance created")

	surface_result, surface := platform.surface_creation(vulkan.instance, window)
	if surface_result != vk.Result.SUCCESS {
		fmt.println("failed to create window surface", surface_result)
		return false
	}
	vulkan.surface = surface
	fmt.println("surface created")

	gpu_count: u32
	result = vk.EnumeratePhysicalDevices(vulkan.instance, &gpu_count, nil)
	if result != vk.Result.SUCCESS || gpu_count == 0 {
		fmt.println("failed to enumerate GPUs", result)
		return false
	}

	devices := make([]vk.PhysicalDevice, gpu_count)
	defer delete(devices)

	result = vk.EnumeratePhysicalDevices(vulkan.instance, &gpu_count, &devices[0])
	if result != vk.Result.SUCCESS {
		fmt.println("failed to get GPU handles", result)
		return false
	}
	vulkan.gpu = devices[0]

	extension_count: u32
	result = vk.EnumerateInstanceExtensionProperties(nil, &extension_count, nil)
	if result != vk.Result.SUCCESS || extension_count == 0 {
		fmt.println("failed to enumerate extensions", result)
		return false
	}

	ta := context.temp_allocator
	extensions := make([]vk.ExtensionProperties, extension_count, ta)
	result = vk.EnumerateInstanceExtensionProperties(nil, &extension_count, raw_data(extensions))
	if result != vk.Result.SUCCESS {
		fmt.println("Failed to enumerate instance extension properties", result)
		return false
	}

	has_surface := false
	has_platform_surface := false
	for &ext in extensions {
		ext_name := byte_arr_str(&ext.extensionName)
		if ext_name == "VK_KHR_surface" {
			has_surface = true
		} else if strings.contains(ext_name, "surface") {
			has_platform_surface = true
		}
	}
	if !has_surface || !has_platform_surface {
		fmt.println("missing required extension")
		return false
	}

	queue_family_count: u32
	vk.GetPhysicalDeviceQueueFamilyProperties(vulkan.gpu, &queue_family_count, nil)

	queue_families := make([]vk.QueueFamilyProperties, queue_family_count)
	defer delete(queue_families)
	vk.GetPhysicalDeviceQueueFamilyProperties(
		vulkan.gpu,
		&queue_family_count,
		raw_data(queue_families),
	)

	graphics_queue_family: u32 = max(u32)
	present_supported: b32 = false

	for i := u32(0); i < queue_family_count; i += 1 {
		flags := queue_families[i].queueFlags
		if flags == {.GRAPHICS} ||
		   flags == {.GRAPHICS, .COMPUTE} ||
		   flags == {.GRAPHICS, .TRANSFER} {
			support_result := vk.GetPhysicalDeviceSurfaceSupportKHR(
				vulkan.gpu,
				i,
				vulkan.surface,
				&present_supported,
			)
			if support_result == vk.Result.SUCCESS && present_supported {
				graphics_queue_family = i
				break
			}
		}
	}

	if graphics_queue_family == max(u32) {
		fmt.println("failed to find suitable queue family")
		return false
	}
	vulkan.queue_family_index = graphics_queue_family

	queue_priority: f32 = 1.0
	queue_create_info := vk.DeviceQueueCreateInfo {
		sType            = vk.StructureType.DEVICE_QUEUE_CREATE_INFO,
		queueFamilyIndex = graphics_queue_family,
		queueCount       = 1,
		pQueuePriorities = &queue_priority,
	}

	device_features := vk.PhysicalDeviceFeatures{}

	device_create_info := vk.DeviceCreateInfo {
		sType                = vk.StructureType.DEVICE_CREATE_INFO,
		queueCreateInfoCount = 1,
		pQueueCreateInfos    = &queue_create_info,
		pEnabledFeatures     = &device_features,
	}

	result = vk.CreateDevice(vulkan.gpu, &device_create_info, nil, &vulkan.device)
	if result != vk.Result.SUCCESS {
		fmt.println("failed to create logical device", result)
		return false
	}
	fmt.println("device created")

	vk.GetDeviceQueue(vulkan.device, vulkan.queue_family_index, 0, &vulkan.graphics_queue)

	fmt.println("getting surface capabilities...")

	surface_capabilities: vk.SurfaceCapabilitiesKHR
	vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(vulkan.gpu, vulkan.surface, &surface_capabilities)

	format_count: u32
	vk.GetPhysicalDeviceSurfaceFormatsKHR(vulkan.gpu, vulkan.surface, &format_count, nil)

	surface_formats := make([]vk.SurfaceFormatKHR, format_count)
	defer delete(surface_formats)
	vk.GetPhysicalDeviceSurfaceFormatsKHR(
		vulkan.gpu,
		vulkan.surface,
		&format_count,
		raw_data(surface_formats),
	)

	present_mode_count: u32
	vk.GetPhysicalDeviceSurfacePresentModesKHR(
		vulkan.gpu,
		vulkan.surface,
		&present_mode_count,
		nil,
	)

	present_modes := make([]vk.PresentModeKHR, present_mode_count)
	defer delete(present_modes)
	vk.GetPhysicalDeviceSurfacePresentModesKHR(
		vulkan.gpu,
		vulkan.surface,
		&present_mode_count,
		raw_data(present_modes),
	)

	chosen_format_found: bool
	for fmt in surface_formats {
		if fmt.format == vk.Format.B8G8R8A8_UNORM &&
		   fmt.colorSpace == vk.ColorSpaceKHR.SRGB_NONLINEAR {
			vulkan.chosen_format = fmt
			chosen_format_found = true
			break
		}
	}
	if !chosen_format_found {
		vulkan.chosen_format = surface_formats[0]
	}

	vulkan.swapchain_extent = surface_capabilities.currentExtent
	if vulkan.swapchain_extent.width == max(u32) || vulkan.swapchain_extent.height == max(u32) {
		vulkan.swapchain_extent = vk.Extent2D {
			width  = 512,
			height = 512,
		}
	}

	image_count := surface_capabilities.minImageCount
	if image_count < 2 {
		image_count = 2
	}

	swapchain_create_info := vk.SwapchainCreateInfoKHR {
		sType            = vk.StructureType.SWAPCHAIN_CREATE_INFO_KHR,
		surface          = vulkan.surface,
		minImageCount    = image_count,
		imageFormat      = vulkan.chosen_format.format,
		imageColorSpace  = vulkan.chosen_format.colorSpace,
		imageExtent      = vulkan.swapchain_extent,
		imageUsage       = {.COLOR_ATTACHMENT},
		imageSharingMode = .EXCLUSIVE,
		compositeAlpha   = {.OPAQUE},
		presentMode      = .FIFO,
		clipped          = true,
		oldSwapchain     = vk.SwapchainKHR(0),
	}

	result = vk.CreateSwapchainKHR(vulkan.device, &swapchain_create_info, nil, &vulkan.swapchain)
	if result != vk.Result.SUCCESS {
		fmt.println("failed to create swapchain", result)
		return false
	}

	swapchain_image_count: u32
	vk.GetSwapchainImagesKHR(vulkan.device, vulkan.swapchain, &swapchain_image_count, nil)

	vulkan.swapchain_images = make([]vk.Image, swapchain_image_count)
	vk.GetSwapchainImagesKHR(
		vulkan.device,
		vulkan.swapchain,
		&swapchain_image_count,
		raw_data(vulkan.swapchain_images),
	)

	vulkan.swapchain_image_views = make([]vk.ImageView, swapchain_image_count)
	for i in 0 ..< swapchain_image_count {
		view_info := vk.ImageViewCreateInfo {
			sType = vk.StructureType.IMAGE_VIEW_CREATE_INFO,
			image = vulkan.swapchain_images[i],
			viewType = .D2,
			format = vulkan.chosen_format.format,
			subresourceRange = vk.ImageSubresourceRange {
				aspectMask = {.COLOR},
				baseMipLevel = 0,
				levelCount = 1,
				baseArrayLayer = 0,
				layerCount = 1,
			},
		}
		result = vk.CreateImageView(
			vulkan.device,
			&view_info,
			nil,
			&vulkan.swapchain_image_views[i],
		)
		if result != vk.Result.SUCCESS {
			fmt.println("failed to create image view", result)
			return false
		}
	}

	attachment_desc := vk.AttachmentDescription {
		format         = vulkan.chosen_format.format,
		samples        = {._1},
		loadOp         = .CLEAR,
		storeOp        = .STORE,
		stencilLoadOp  = .DONT_CARE,
		stencilStoreOp = .DONT_CARE,
		initialLayout  = .UNDEFINED,
		finalLayout    = .PRESENT_SRC_KHR,
	}
	subpass_desc := vk.SubpassDescription {
		pipelineBindPoint    = .GRAPHICS,
		colorAttachmentCount = 1,
		pColorAttachments    = &vk.AttachmentReference {
			attachment = 0,
			layout = .COLOR_ATTACHMENT_OPTIMAL,
		},
	}
	render_pass_info := vk.RenderPassCreateInfo {
		sType           = vk.StructureType.RENDER_PASS_CREATE_INFO,
		attachmentCount = 1,
		pAttachments    = &attachment_desc,
		subpassCount    = 1,
		pSubpasses      = &subpass_desc,
	}
	result = vk.CreateRenderPass(vulkan.device, &render_pass_info, nil, &vulkan.render_pass)
	if result != vk.Result.SUCCESS {
		fmt.println("failed to create render pass", result)
		return false
	}

	vulkan.framebuffers = make([]vk.Framebuffer, swapchain_image_count)
	for i in 0 ..< swapchain_image_count {
		fb_info := vk.FramebufferCreateInfo {
			sType           = vk.StructureType.FRAMEBUFFER_CREATE_INFO,
			renderPass      = vulkan.render_pass,
			attachmentCount = 1,
			pAttachments    = &vulkan.swapchain_image_views[i],
			width           = vulkan.swapchain_extent.width,
			height          = vulkan.swapchain_extent.height,
			layers          = 1,
		}
		result = vk.CreateFramebuffer(vulkan.device, &fb_info, nil, &vulkan.framebuffers[i])
		if result != vk.Result.SUCCESS {
			fmt.println("failed to create framebuffer", result)
			return false
		}
	}

	pool_info := vk.CommandPoolCreateInfo {
		sType            = vk.StructureType.COMMAND_POOL_CREATE_INFO,
		queueFamilyIndex = vulkan.queue_family_index,
		flags            = {},
	}
	result = vk.CreateCommandPool(vulkan.device, &pool_info, nil, &vulkan.command_pool)
	if result != vk.Result.SUCCESS {
		fmt.println("failed to create command pool", result)
		return false
	}

	vulkan.command_buffers = make([]vk.CommandBuffer, swapchain_image_count)
	alloc_info := vk.CommandBufferAllocateInfo {
		sType              = vk.StructureType.COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = vulkan.command_pool,
		level              = .PRIMARY,
		commandBufferCount = swapchain_image_count,
	}
	result = vk.AllocateCommandBuffers(
		vulkan.device,
		&alloc_info,
		raw_data(vulkan.command_buffers),
	)
	if result != vk.Result.SUCCESS {
		fmt.println("failed to allocate command buffers", result)
		return false
	}

	semaphore_info := vk.SemaphoreCreateInfo {
		sType = vk.StructureType.SEMAPHORE_CREATE_INFO,
	}
	vk.CreateSemaphore(vulkan.device, &semaphore_info, nil, &app.acquired_semaphore)

	return true
}

cleanup_vulkan :: proc(app: ^AppRunner) {
	vulkan := &app.vulkan

	if app.acquired_semaphore != vk.Semaphore(0) {
		vk.DestroySemaphore(vulkan.device, app.acquired_semaphore, nil)
	}

	if vulkan.command_pool != vk.CommandPool(0) {
		vk.DestroyCommandPool(vulkan.device, vulkan.command_pool, nil)
	}

	if len(vulkan.framebuffers) > 0 {
		for fb in vulkan.framebuffers {
			vk.DestroyFramebuffer(vulkan.device, fb, nil)
		}
		delete(vulkan.framebuffers)
	}

	if vulkan.render_pass != vk.RenderPass(0) {
		vk.DestroyRenderPass(vulkan.device, vulkan.render_pass, nil)
	}

	for view in vulkan.swapchain_image_views {
		vk.DestroyImageView(vulkan.device, view, nil)
	}
	delete(vulkan.swapchain_image_views)

	if vulkan.swapchain != vk.SwapchainKHR(0) {
		vk.DestroySwapchainKHR(vulkan.device, vulkan.swapchain, nil)
	}

	if vulkan.device != nil {
		vk.DestroyDevice(vulkan.device, nil)
	}

	if vulkan.surface != vk.SurfaceKHR(0) {
		vk.DestroySurfaceKHR(vulkan.instance, vulkan.surface, nil)
	}

	if vulkan.instance != nil {
		vk.DestroyInstance(vulkan.instance, nil)
	}
}

run_main_loop :: proc(app: ^AppRunner) {
	vulkan := &app.vulkan

	fmt.println("entering main loop")

	for !glfw.WindowShouldClose(app.window) {
		glfw.PollEvents()

		image_index: u32
		acquire_result := vk.AcquireNextImageKHR(
			vulkan.device,
			vulkan.swapchain,
			max(u64),
			app.acquired_semaphore,
			vk.Fence(0),
			&image_index,
		)
		if acquire_result != vk.Result.SUCCESS && acquire_result != vk.Result(0x00000BB9) {
			continue
		}

		vk.ResetCommandBuffer(vulkan.command_buffers[image_index], {})

		begin_info := vk.CommandBufferBeginInfo {
			sType = vk.StructureType.COMMAND_BUFFER_BEGIN_INFO,
		}
		vk.BeginCommandBuffer(vulkan.command_buffers[image_index], &begin_info)

		clear_value := vk.ClearValue {
			color = vk.ClearColorValue{float32 = {0.0, 0.0, 0.0, 1.0}},
		}
		render_area := vk.Rect2D {
			offset = vk.Offset2D{x = 0, y = 0},
			extent = vulkan.swapchain_extent,
		}
		render_pass_begin := vk.RenderPassBeginInfo {
			sType           = vk.StructureType.RENDER_PASS_BEGIN_INFO,
			renderPass      = vulkan.render_pass,
			framebuffer     = vulkan.framebuffers[image_index],
			renderArea      = render_area,
			clearValueCount = 1,
			pClearValues    = &clear_value,
		}
		vk.CmdBeginRenderPass(
			vulkan.command_buffers[image_index],
			&render_pass_begin,
			vk.SubpassContents.INLINE,
		)
		vk.CmdEndRenderPass(vulkan.command_buffers[image_index])
		vk.EndCommandBuffer(vulkan.command_buffers[image_index])

		wait_sems := []vk.Semaphore{app.acquired_semaphore}
		cmd_buf := []vk.CommandBuffer{vulkan.command_buffers[image_index]}
		submit_info := vk.SubmitInfo {
			sType              = vk.StructureType.SUBMIT_INFO,
			waitSemaphoreCount = 1,
			pWaitSemaphores    = raw_data(wait_sems),
			commandBufferCount = 1,
			pCommandBuffers    = raw_data(cmd_buf),
		}
		vk.QueueSubmit(vulkan.graphics_queue, 1, &submit_info, vk.Fence(0))

		present_sems := []vk.Semaphore{app.acquired_semaphore}
		present_idx := []u32{image_index}
		present_info := vk.PresentInfoKHR {
			sType              = vk.StructureType.PRESENT_INFO_KHR,
			waitSemaphoreCount = 1,
			pWaitSemaphores    = raw_data(present_sems),
			swapchainCount     = 1,
			pSwapchains        = &vulkan.swapchain,
			pImageIndices      = raw_data(present_idx),
		}
		vk.QueuePresentKHR(vulkan.graphics_queue, &present_info)
	}
}

main :: proc() {
	fmt.println("starting engine...")
	if glfw.Init() != true {
		fmt.println("failed to initialize glfw")
		return
	}
	defer glfw.Terminate()

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	glfw.WindowHint(glfw.RESIZABLE, 1)

	window := glfw.CreateWindow(512, 512, "Test Engine", nil, nil)
	if window == nil {
		fmt.println("failed to create window")
		return
	}
	defer glfw.DestroyWindow(window)

	app := AppRunner {
		window   = window,
		platform = get_platform_info(),
	}

	ok := init_vulkan_context(&app)
	if !ok {
		fmt.println("failed to initialize vulkan")
		return
	}
	defer cleanup_vulkan(&app)

	run_main_loop(&app)
}
