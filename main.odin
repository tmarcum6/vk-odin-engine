package main

import "core:fmt"
import "core:strings"
import "vendor:glfw"
import vk "vendor:vulkan"

byte_arr_str :: proc(arr: ^[$N]byte) -> string {
	return strings.truncate_to_byte(string(arr[:]), 0)
}

init_vulkan :: proc(
	instance: ^vk.Instance,
	window: glfw.WindowHandle,
) -> (
	bool,
	vk.PhysicalDevice,
	vk.SurfaceKHR,
	u32,
	vk.Device,
	vk.SwapchainKHR,
	vk.RenderPass,
	vk.CommandPool,
	[]vk.CommandBuffer,
) {
	create_info := vk.InstanceCreateInfo {
		sType            = vk.StructureType.INSTANCE_CREATE_INFO,
		pApplicationInfo = &vk.ApplicationInfo {
			sType = vk.StructureType.APPLICATION_INFO,
			pApplicationName = "Test Engine",
			applicationVersion = vk.MAKE_VERSION(1, 0, 0),
			apiVersion = vk.API_VERSION_1_0,
		},
	}

	exts := glfw.GetRequiredInstanceExtensions()
	create_info.enabledExtensionCount = 1
	create_info.ppEnabledExtensionNames = raw_data(exts)

	supported_versions: u32
	result := vk.EnumerateInstanceVersion(&supported_versions)
	if result != vk.Result.SUCCESS {
		fmt.println("failed to enumerate vulkan instance version", result)
		return false, nil, vk.SurfaceKHR(0), 0, nil, vk.SwapchainKHR(0), vk.RenderPass(0), vk.CommandPool(0), nil
	}

	result = vk.CreateInstance(&create_info, nil, instance)
	if result != vk.Result.SUCCESS {
		fmt.println("failed to create vulkan instance", result)
		return false, nil, vk.SurfaceKHR(0), 0, nil, vk.SwapchainKHR(0), vk.RenderPass(0), vk.CommandPool(0), nil
	}

	surface: vk.SurfaceKHR
	result = glfw.CreateWindowSurface(instance^, window, nil, &surface)
	if result != vk.Result.SUCCESS {
		fmt.println("failed to create window surface", result)
		return false, nil, vk.SurfaceKHR(0), 0, nil, vk.SwapchainKHR(0), vk.RenderPass(0), vk.CommandPool(0), nil
	}

	gpu_count: u32
	result = vk.EnumeratePhysicalDevices(instance^, &gpu_count, nil)
	if result != vk.Result.SUCCESS {
		fmt.println("failed to enumerate GPUs", result)
		return false, nil, vk.SurfaceKHR(0), 0, nil, vk.SwapchainKHR(0), vk.RenderPass(0), vk.CommandPool(0), nil
	}

	if gpu_count == 0 {fmt.println("no GPUs found"); return false, nil, vk.SurfaceKHR(0), 0, nil, vk.SwapchainKHR(0), vk.RenderPass(0), vk.CommandPool(0), nil}

	devices := make([]vk.PhysicalDevice, gpu_count)
	defer delete(devices)

	result = vk.EnumeratePhysicalDevices(instance^, &gpu_count, &devices[0])
	if result != vk.Result.SUCCESS {
		fmt.println("failed to get GPU handles", result)
		return false, nil, vk.SurfaceKHR(0), 0, nil, vk.SwapchainKHR(0), vk.RenderPass(0), vk.CommandPool(0), nil
	}

	extension_count: u32
	result = vk.EnumerateInstanceExtensionProperties(nil, &extension_count, nil)
	if result != vk.Result.SUCCESS {
		fmt.println("failed to enumerate extensions", result)
		return false, nil, vk.SurfaceKHR(0), 0, nil, vk.SwapchainKHR(0), vk.RenderPass(0), vk.CommandPool(0), nil
	}

	if extension_count ==
	   0 {fmt.println("no extensions found"); return false, nil, vk.SurfaceKHR(0), 0, nil, vk.SwapchainKHR(0), vk.RenderPass(0), vk.CommandPool(0), nil}

	ta := context.temp_allocator

	if extension_count > 0 {
		extensions := make([]vk.ExtensionProperties, extension_count, ta)
		result = vk.EnumerateInstanceExtensionProperties(
			nil,
			&extension_count,
			raw_data(extensions),
		)
		if result != vk.Result.SUCCESS {
			fmt.println("Failed to enumerate instance extension properties", result)
			return false, nil, vk.SurfaceKHR(0), 0, nil, vk.SwapchainKHR(0), vk.RenderPass(0), vk.CommandPool(0), nil
		}

		has_surface := false
		has_macos_surface := false
		for &ext in extensions {
			ext_name := byte_arr_str(&ext.extensionName)
			if ext_name == "VK_KHR_surface" {
				has_surface = true
			} else if ext_name == "VK_MVK_macos_surface" {
				has_macos_surface = true
			}
		}
		if !has_surface || !has_macos_surface {
			fmt.println("missing required extension")
			return false, nil, vk.SurfaceKHR(0), 0, nil, vk.SwapchainKHR(0), vk.RenderPass(0), vk.CommandPool(0), nil
		}
	}

	queue_family_count: u32
	vk.GetPhysicalDeviceQueueFamilyProperties(devices[0], &queue_family_count, nil)

	queue_families := make([]vk.QueueFamilyProperties, queue_family_count)
	defer delete(queue_families)
	vk.GetPhysicalDeviceQueueFamilyProperties(
		devices[0],
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
				devices[0],
				i,
				surface,
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
		return false, nil, vk.SurfaceKHR(0), 0, nil, vk.SwapchainKHR(0), vk.RenderPass(0), vk.CommandPool(0), nil
	}

	queue_priority: f32 = 1.0
	queue_create_info := vk.DeviceQueueCreateInfo {
		sType = vk.StructureType.DEVICE_QUEUE_CREATE_INFO,
		queueFamilyIndex = graphics_queue_family,
		queueCount = 1,
		pQueuePriorities = &queue_priority,
	}

	device_features := vk.PhysicalDeviceFeatures {}

	device_create_info := vk.DeviceCreateInfo {
		sType = vk.StructureType.DEVICE_CREATE_INFO,
		queueCreateInfoCount = 1,
		pQueueCreateInfos = &queue_create_info,
		pEnabledFeatures = &device_features,
	}

device: vk.Device
	result = vk.CreateDevice(devices[0], &device_create_info, nil, &device)
	if result != vk.Result.SUCCESS {
		fmt.println("failed to create logical device", result)
		return false, nil, vk.SurfaceKHR(0), 0, nil, vk.SwapchainKHR(0), vk.RenderPass(0), vk.CommandPool(0), nil
	}

	surface_capabilities: vk.SurfaceCapabilitiesKHR
	vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(devices[0], surface, &surface_capabilities)

	format_count: u32
	vk.GetPhysicalDeviceSurfaceFormatsKHR(devices[0], surface, &format_count, nil)

	surface_formats := make([]vk.SurfaceFormatKHR, format_count)
	defer delete(surface_formats)
	vk.GetPhysicalDeviceSurfaceFormatsKHR(devices[0], surface, &format_count, raw_data(surface_formats))

	present_mode_count: u32
	vk.GetPhysicalDeviceSurfacePresentModesKHR(devices[0], surface, &present_mode_count, nil)

	present_modes := make([]vk.PresentModeKHR, present_mode_count)
	defer delete(present_modes)
	vk.GetPhysicalDeviceSurfacePresentModesKHR(devices[0], surface, &present_mode_count, raw_data(present_modes))

	chosen_format: vk.SurfaceFormatKHR
	chosen_format_found: bool
	for fmt in surface_formats {
		if fmt.format == vk.Format.B8G8R8A8_UNORM && fmt.colorSpace == vk.ColorSpaceKHR.SRGB_NONLINEAR {
			chosen_format = fmt
			chosen_format_found = true
			break
		}
	}
	if !chosen_format_found {
		chosen_format = surface_formats[0]
	}

	chosen_present_mode: vk.PresentModeKHR = .FIFO
	for pm in present_modes {
		if pm == vk.PresentModeKHR.FIFO {
			chosen_present_mode = pm
			break
		}
	}

	swapchain_width := surface_capabilities.currentExtent.width
	swapchain_height := surface_capabilities.currentExtent.height
	if swapchain_width == max(u32) || swapchain_height == max(u32) {
		swapchain_width = 512
		swapchain_height = 512
	}

	image_count := surface_capabilities.minImageCount
	if image_count < 2 {
		image_count = 2
	}

	swapchain_create_info := vk.SwapchainCreateInfoKHR {
		sType = vk.StructureType.SWAPCHAIN_CREATE_INFO_KHR,
		surface = surface,
		minImageCount = image_count,
		imageFormat = chosen_format.format,
		imageColorSpace = chosen_format.colorSpace,
		imageExtent = vk.Extent2D{width = swapchain_width, height = swapchain_height},
		imageUsage = {.COLOR_ATTACHMENT},
		imageSharingMode = .EXCLUSIVE,
		compositeAlpha = {.OPAQUE},
		presentMode = chosen_present_mode,
		clipped = true,
		oldSwapchain = vk.SwapchainKHR(0),
	}

swapchain: vk.SwapchainKHR
	result = vk.CreateSwapchainKHR(device, &swapchain_create_info, nil, &swapchain)
	if result != vk.Result.SUCCESS {
		fmt.println("failed to create swapchain", result)
		return false, nil, vk.SurfaceKHR(0), 0, nil, vk.SwapchainKHR(0), vk.RenderPass(0), vk.CommandPool(0), nil
	}

	render_pass: vk.RenderPass
	attachment_desc := vk.AttachmentDescription {
		format = chosen_format.format,
		samples = {._1},
		loadOp = .CLEAR,
		storeOp = .STORE,
		stencilLoadOp = .DONT_CARE,
		stencilStoreOp = .DONT_CARE,
		initialLayout = .UNDEFINED,
		finalLayout = .PRESENT_SRC_KHR,
	}
	subpass_desc := vk.SubpassDescription {
		pipelineBindPoint = .GRAPHICS,
		colorAttachmentCount = 1,
		pColorAttachments = &vk.AttachmentReference{
			attachment = 0,
			layout = .COLOR_ATTACHMENT_OPTIMAL,
		},
	}
	render_pass_info := vk.RenderPassCreateInfo {
		sType = vk.StructureType.RENDER_PASS_CREATE_INFO,
		attachmentCount = 1,
		pAttachments = &attachment_desc,
		subpassCount = 1,
		pSubpasses = &subpass_desc,
	}
	result = vk.CreateRenderPass(device, &render_pass_info, nil, &render_pass)
	if result != vk.Result.SUCCESS {
		fmt.println("failed to create render pass", result)
		return false, nil, vk.SurfaceKHR(0), 0, nil, vk.SwapchainKHR(0), vk.RenderPass(0), vk.CommandPool(0), nil
	}

	swapchain_image_count: u32
	vk.GetSwapchainImagesKHR(device, swapchain, &swapchain_image_count, nil)

	swapchain_images := make([]vk.Image, swapchain_image_count)
	defer delete(swapchain_images)
	vk.GetSwapchainImagesKHR(device, swapchain, &swapchain_image_count, raw_data(swapchain_images))

	swapchain_image_views := make([]vk.ImageView, swapchain_image_count)
	defer delete(swapchain_image_views)
	for i in 0..<swapchain_image_count {
		view_info := vk.ImageViewCreateInfo {
			sType = vk.StructureType.IMAGE_VIEW_CREATE_INFO,
			image = swapchain_images[i],
			viewType = .D2,
			format = chosen_format.format,
			subresourceRange = vk.ImageSubresourceRange {
				aspectMask = {.COLOR},
				baseMipLevel = 0,
				levelCount = 1,
				baseArrayLayer = 0,
				layerCount = 1,
			},
		}
		result = vk.CreateImageView(device, &view_info, nil, &swapchain_image_views[i])
		if result != vk.Result.SUCCESS {
			fmt.println("failed to create image view", result)
			return false, nil, vk.SurfaceKHR(0), 0, nil, vk.SwapchainKHR(0), vk.RenderPass(0), vk.CommandPool(0), nil
		}
	}

	command_pool: vk.CommandPool
	pool_info := vk.CommandPoolCreateInfo {
		sType = vk.StructureType.COMMAND_POOL_CREATE_INFO,
		queueFamilyIndex = graphics_queue_family,
		flags = {},
	}
	result = vk.CreateCommandPool(device, &pool_info, nil, &command_pool)
	if result != vk.Result.SUCCESS {
		fmt.println("failed to create command pool", result)
		return false, nil, vk.SurfaceKHR(0), 0, nil, vk.SwapchainKHR(0), vk.RenderPass(0), vk.CommandPool(0), nil
	}

	command_buffers := make([]vk.CommandBuffer, swapchain_image_count)
	defer delete(command_buffers)
	alloc_info := vk.CommandBufferAllocateInfo {
		sType = vk.StructureType.COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool = command_pool,
		level = .PRIMARY,
		commandBufferCount = swapchain_image_count,
	}
	result = vk.AllocateCommandBuffers(device, &alloc_info, raw_data(command_buffers))
	if result != vk.Result.SUCCESS {
		fmt.println("failed to allocate command buffers", result)
		return false, nil, vk.SurfaceKHR(0), 0, nil, vk.SwapchainKHR(0), vk.RenderPass(0), vk.CommandPool(0), nil
	}

	return true, devices[0], surface, graphics_queue_family, device, swapchain, render_pass, command_pool, command_buffers
}

main :: proc() {

	if (glfw.Init() != true) {
		fmt.println("failed to initialize glfw")
		return
	}
	defer glfw.Terminate()

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	glfw.WindowHint(glfw.RESIZABLE, 1)

	window := glfw.CreateWindow(512, 512, "Test Engine", nil, nil)
	defer glfw.DestroyWindow(window)

	if window == nil {
		fmt.println("failed to create window")
		return
	}

	instance: vk.Instance
	ok, gpu, surface, queue_family_index, device, swapchain, render_pass, command_pool, command_buffers := init_vulkan(&instance, window)
	if !ok {
		fmt.println("failed to initialize vulkan")
		return
	}

	graphics_queue: vk.Queue
	vk.GetDeviceQueue(device, queue_family_index, 0, &graphics_queue)

	acquired_semaphore: vk.Semaphore
	semaphore_info := vk.SemaphoreCreateInfo{sType = vk.StructureType.SEMAPHORE_CREATE_INFO}
	vk.CreateSemaphore(device, &semaphore_info, nil, &acquired_semaphore)

	for !glfw.WindowShouldClose(window) {
		glfw.PollEvents()

		image_index: u32
		acquire_result := vk.AcquireNextImageKHR(device, swapchain, max(u64), acquired_semaphore, vk.Fence(0), &image_index)
		if acquire_result != vk.Result.SUCCESS && acquire_result != vk.Result(0x00000BB9) {
			continue
		}

		vk.ResetCommandBuffer(command_buffers[image_index], {})

		begin_info := vk.CommandBufferBeginInfo{
			sType = vk.StructureType.COMMAND_BUFFER_BEGIN_INFO,
		}
		vk.BeginCommandBuffer(command_buffers[image_index], &begin_info)

		clear_value := vk.ClearValue{color = vk.ClearColorValue{float32 = {0.0, 0.0, 0.0, 1.0}}}
		render_area := vk.Rect2D{
			offset = vk.Offset2D{x = 0, y = 0},
			extent = vk.Extent2D{width = 512, height = 512},
		}
		render_pass_begin := vk.RenderPassBeginInfo{
			sType = vk.StructureType.RENDER_PASS_BEGIN_INFO,
			renderPass = render_pass,
			framebuffer = vk.Framebuffer(0),
			renderArea = render_area,
			clearValueCount = 1,
			pClearValues = &clear_value,
		}
		vk.CmdBeginRenderPass(command_buffers[image_index], &render_pass_begin, vk.SubpassContents.INLINE)
		vk.CmdEndRenderPass(command_buffers[image_index])
		vk.EndCommandBuffer(command_buffers[image_index])

		wait_sems := []vk.Semaphore{acquired_semaphore}
		cmd_buf := []vk.CommandBuffer{command_buffers[image_index]}
		submit_info := vk.SubmitInfo{
			sType = vk.StructureType.SUBMIT_INFO,
			waitSemaphoreCount = 1,
			pWaitSemaphores = raw_data(wait_sems),
			commandBufferCount = 1,
			pCommandBuffers = raw_data(cmd_buf),
		}
		vk.QueueSubmit(graphics_queue, 1, &submit_info, vk.Fence(0))

		present_sems := []vk.Semaphore{acquired_semaphore}
		present_idx := []u32{image_index}
		present_info := vk.PresentInfoKHR{
			sType = vk.StructureType.PRESENT_INFO_KHR,
			waitSemaphoreCount = 1,
			pWaitSemaphores = raw_data(present_sems),
			swapchainCount = 1,
			pSwapchains = &swapchain,
			pImageIndices = raw_data(present_idx),
		}
		vk.QueuePresentKHR(graphics_queue, &present_info)
	}
}
