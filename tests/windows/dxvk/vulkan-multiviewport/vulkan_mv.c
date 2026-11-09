// vulkan_mv.c —— 原生 Vulkan 多视口（multiViewport + gl_ViewportIndex）实测
// 离屏渲染：左半屏红色、右半屏绿色（两个不同 viewport），像素回读校验。
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <vulkan/vulkan.h>

#define W 64
#define H 64
#define CHECK(x) do { VkResult r = (x); if (r != VK_SUCCESS) { printf("FAIL %s -> %d\n", #x, r); return 20; } } while (0)

static VkInstance inst;
static VkPhysicalDevice phys;
static VkDevice dev;
static VkQueue queue;
static uint32_t qfam;

static int pick_device(const char *want) {
    uint32_t n = 0;
    vkEnumeratePhysicalDevices(inst, &n, NULL);
    if (!n) return -1;
    VkPhysicalDevice *pds = calloc(n, sizeof(*pds));
    vkEnumeratePhysicalDevices(inst, &n, pds);
    int idx = -1;
    for (uint32_t i = 0; i < n; i++) {
        VkPhysicalDeviceProperties p;
        vkGetPhysicalDeviceProperties(pds[i], &p);
        printf("DEVICE[%u]=%s type=%d api=%u.%u.%u\n", i, p.deviceName, p.deviceType,
               VK_VERSION_MAJOR(p.apiVersion), VK_VERSION_MINOR(p.apiVersion), VK_VERSION_PATCH(p.apiVersion));
        if (want && strstr(p.deviceName, want)) idx = (int)i;
        else if (!want && idx < 0 && p.deviceType != VK_PHYSICAL_DEVICE_TYPE_CPU) idx = (int)i;
    }
    if (idx >= 0) phys = pds[idx];
    free(pds);
    return idx;
}

int main(int argc, char **argv) {
    const char *want = (argc > 1) ? argv[1] : "Turnip";

    VkApplicationInfo ai = {VK_STRUCTURE_TYPE_APPLICATION_INFO};
    ai.apiVersion = VK_API_VERSION_1_1;
    VkInstanceCreateInfo ici = {VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO};
    ici.pApplicationInfo = &ai;
    CHECK(vkCreateInstance(&ici, NULL, &inst));

    if (pick_device(want) < 0) { printf("NO_DEVICE\n"); return 10; }

    VkPhysicalDeviceFeatures2 f2 = {VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2};
    vkGetPhysicalDeviceFeatures2(phys, &f2);
    printf("FEATURES multiViewport=%d\n", f2.features.multiViewport);

    // 查看设备扩展是否提供 shader viewport index
    uint32_t extn = 0;
    vkEnumerateDeviceExtensionProperties(phys, NULL, &extn, NULL);
    VkExtensionProperties *exts = calloc(extn, sizeof(*exts));
    vkEnumerateDeviceExtensionProperties(phys, NULL, &extn, exts);
    int has_vpi = 0;
    for (uint32_t i = 0; i < extn; i++)
        if (!strcmp(exts[i].extensionName, "VK_EXT_shader_viewport_index_layer")) has_vpi = 1;
    free(exts);
    printf("EXT_shader_viewport_index_layer=%d\n", has_vpi);

    VkPhysicalDeviceProperties p;
    vkGetPhysicalDeviceProperties(phys, &p);
    printf("LIMITS maxViewports=%u\n", p.limits.maxViewports);

    if (!f2.features.multiViewport) { printf("RESULT=UNSUPPORTED\n"); return 11; }

    uint32_t qn = 0;
    vkGetPhysicalDeviceQueueFamilyProperties(phys, &qn, NULL);
    VkQueueFamilyProperties *qf = calloc(qn, sizeof(*qf));
    vkGetPhysicalDeviceQueueFamilyProperties(phys, &qn, qf);
    qfam = UINT32_MAX;
    for (uint32_t i = 0; i < qn; i++) if (qf[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) { qfam = i; break; }
    free(qf);
    if (qfam == UINT32_MAX) { printf("NO_QUEUE\n"); return 12; }

    float prio = 1.0f;
    VkDeviceQueueCreateInfo qci = {VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO};
    qci.queueFamilyIndex = qfam; qci.queueCount = 1; qci.pQueuePriorities = &prio;
    VkPhysicalDeviceFeatures feats = {0};
    feats.multiViewport = VK_TRUE;
    const char *devexts[1] = {"VK_EXT_shader_viewport_index_layer"};
    VkDeviceCreateInfo dci = {VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO};
    dci.queueCreateInfoCount = 1; dci.pQueueCreateInfos = &qci;
    dci.pEnabledFeatures = &feats;
    if (has_vpi) { dci.enabledExtensionCount = 1; dci.ppEnabledExtensionNames = devexts; }
    CHECK(vkCreateDevice(phys, &dci, NULL, &dev));
    vkGetDeviceQueue(dev, qfam, 0, &queue);

    VkImageCreateInfo imgci = {VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO};
    imgci.imageType = VK_IMAGE_TYPE_2D;
    imgci.format = VK_FORMAT_R8G8B8A8_UNORM;
    imgci.extent = (VkExtent3D){W, H, 1};
    imgci.mipLevels = 1; imgci.arrayLayers = 1;
    imgci.samples = VK_SAMPLE_COUNT_1_BIT;
    imgci.tiling = VK_IMAGE_TILING_OPTIMAL;
    imgci.usage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
    imgci.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    VkImage img; CHECK(vkCreateImage(dev, &imgci, NULL, &img));
    VkMemoryRequirements mr; vkGetImageMemoryRequirements(dev, img, &mr);
    VkPhysicalDeviceMemoryProperties mp; vkGetPhysicalDeviceMemoryProperties(phys, &mp);
    uint32_t mt = UINT32_MAX;
    for (uint32_t i = 0; i < mp.memoryTypeCount; i++)
        if ((mr.memoryTypeBits & (1u << i)) && (mp.memoryTypes[i].propertyFlags & VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)) { mt = i; break; }
    if (mt == UINT32_MAX) mt = 0;
    VkMemoryAllocateInfo mai = {VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO};
    mai.allocationSize = mr.size; mai.memoryTypeIndex = mt;
    VkDeviceMemory imgmem; CHECK(vkAllocateMemory(dev, &mai, NULL, &imgmem));
    CHECK(vkBindImageMemory(dev, img, imgmem, 0));
    VkImageViewCreateInfo ivci = {VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO};
    ivci.image = img; ivci.viewType = VK_IMAGE_VIEW_TYPE_2D; ivci.format = imgci.format;
    ivci.subresourceRange = (VkImageSubresourceRange){VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
    VkImageView view; CHECK(vkCreateImageView(dev, &ivci, NULL, &view));

    VkAttachmentDescription att = {0};
    att.format = imgci.format; att.samples = VK_SAMPLE_COUNT_1_BIT;
    att.loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR; att.storeOp = VK_ATTACHMENT_STORE_OP_STORE;
    att.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED; att.finalLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
    VkAttachmentReference ar = {0, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL};
    VkSubpassDescription sp = {0};
    sp.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS;
    sp.colorAttachmentCount = 1; sp.pColorAttachments = &ar;
    VkRenderPassCreateInfo rpci = {VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO};
    rpci.attachmentCount = 1; rpci.pAttachments = &att;
    rpci.subpassCount = 1; rpci.pSubpasses = &sp;
    VkRenderPass rp; CHECK(vkCreateRenderPass(dev, &rpci, NULL, &rp));
    VkFramebufferCreateInfo fbci = {VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO};
    fbci.renderPass = rp; fbci.attachmentCount = 1; fbci.pAttachments = &view;
    fbci.width = W; fbci.height = H; fbci.layers = 1;
    VkFramebuffer fb; CHECK(vkCreateFramebuffer(dev, &fbci, NULL, &fb));

    // 读 shader
    FILE *f = fopen("vert.spv", "rb");
    if (!f) { printf("NO_VERT_SPV\n"); return 13; }
    static char vb[65536]; size_t vsz = fread(vb, 1, sizeof(vb), f); fclose(f);
    f = fopen("frag.spv", "rb");
    if (!f) { printf("NO_FRAG_SPV\n"); return 13; }
    static char fb_[65536]; size_t fsz = fread(fb_, 1, sizeof(fb_), f); fclose(f);

    VkShaderModuleCreateInfo smci = {VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO};
    smci.codeSize = vsz; smci.pCode = (const uint32_t *)vb;
    VkShaderModule vs; CHECK(vkCreateShaderModule(dev, &smci, NULL, &vs));
    smci.codeSize = fsz; smci.pCode = (const uint32_t *)fb_;
    VkShaderModule fs; CHECK(vkCreateShaderModule(dev, &smci, NULL, &fs));

    VkPipelineShaderStageCreateInfo stages[2] = {
        {VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, NULL, 0, VK_SHADER_STAGE_VERTEX_BIT, vs, "main", NULL},
        {VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, NULL, 0, VK_SHADER_STAGE_FRAGMENT_BIT, fs, "main", NULL},
    };
    VkPipelineVertexInputStateCreateInfo vi = {VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO};
    VkPipelineInputAssemblyStateCreateInfo ia = {VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO};
    ia.topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    VkViewport vps[2] = {{0, 0, W / 2.0f, H, 0, 1}, {W / 2.0f, 0, W / 2.0f, H, 0, 1}};
    VkRect2D scis[2] = {{{0, 0}, {W / 2, H}}, {{W / 2, 0}, {W / 2, H}}};
    VkPipelineViewportStateCreateInfo vp = {VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO};
    vp.viewportCount = 2; vp.pViewports = vps; vp.scissorCount = 2; vp.pScissors = scis;
    VkPipelineRasterizationStateCreateInfo rs = {VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO};
    rs.polygonMode = VK_POLYGON_MODE_FILL; rs.cullMode = VK_CULL_MODE_NONE;
    rs.frontFace = VK_FRONT_FACE_COUNTER_CLOCKWISE; rs.lineWidth = 1.0f;
    VkPipelineMultisampleStateCreateInfo ms = {VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO};
    ms.rasterizationSamples = VK_SAMPLE_COUNT_1_BIT;
    VkPipelineColorBlendAttachmentState cba = {0};
    cba.colorWriteMask = 0xF;
    VkPipelineColorBlendStateCreateInfo cb = {VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO};
    cb.attachmentCount = 1; cb.pAttachments = &cba;
    VkPipelineLayoutCreateInfo plci = {VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO};
    VkPipelineLayout pl; CHECK(vkCreatePipelineLayout(dev, &plci, NULL, &pl));
    VkGraphicsPipelineCreateInfo gpci = {VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO};
    gpci.stageCount = 2; gpci.pStages = stages;
    gpci.pVertexInputState = &vi; gpci.pInputAssemblyState = &ia;
    gpci.pViewportState = &vp; gpci.pRasterizationState = &rs;
    gpci.pMultisampleState = &ms; gpci.pColorBlendState = &cb;
    gpci.layout = pl; gpci.renderPass = rp;
    VkPipeline pipe;
    VkResult pr = vkCreateGraphicsPipelines(dev, VK_NULL_HANDLE, 1, &gpci, NULL, &pipe);
    if (pr != VK_SUCCESS) { printf("PIPELINE_FAIL=%d\n", pr); return 14; }
    printf("PIPELINE_CREATED viewports=2\n");

    VkCommandPoolCreateInfo cpci = {VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO};
    cpci.queueFamilyIndex = qfam;
    VkCommandPool pool; CHECK(vkCreateCommandPool(dev, &cpci, NULL, &pool));
    VkCommandBufferAllocateInfo cbai = {VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO};
    cbai.commandPool = pool; cbai.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY; cbai.commandBufferCount = 1;
    VkCommandBuffer cmd; CHECK(vkAllocateCommandBuffers(dev, &cbai, &cmd));

    VkCommandBufferBeginInfo bi = {VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
    vkBeginCommandBuffer(cmd, &bi);
    VkClearValue clear = {{{0, 0, 0, 1}}};
    VkRenderPassBeginInfo rbi = {VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO};
    rbi.renderPass = rp; rbi.framebuffer = fb;
    rbi.renderArea = (VkRect2D){{0, 0}, {W, H}};
    rbi.clearValueCount = 1; rbi.pClearValues = &clear;
    vkCmdBeginRenderPass(cmd, &rbi, VK_SUBPASS_CONTENTS_INLINE);
    vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, pipe);
    vkCmdDraw(cmd, 3, 2, 0, 0);   // 2 instances → 两个 viewport
    vkCmdEndRenderPass(cmd);

    VkBufferCreateInfo bci = {VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO};
    bci.size = W * H * 4; bci.usage = VK_BUFFER_USAGE_TRANSFER_DST_BIT;
    VkBuffer buf; CHECK(vkCreateBuffer(dev, &bci, NULL, &buf));
    VkMemoryRequirements bmr; vkGetBufferMemoryRequirements(dev, buf, &bmr);
    uint32_t bmt = UINT32_MAX;
    for (uint32_t i = 0; i < mp.memoryTypeCount; i++)
        if ((bmr.memoryTypeBits & (1u << i)) && (mp.memoryTypes[i].propertyFlags & VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT)) { bmt = i; break; }
    VkMemoryAllocateInfo bmai = {VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO};
    bmai.allocationSize = bmr.size; bmai.memoryTypeIndex = bmt;
    VkDeviceMemory bmem; CHECK(vkAllocateMemory(dev, &bmai, NULL, &bmem));
    CHECK(vkBindBufferMemory(dev, buf, bmem, 0));
    VkBufferImageCopy cpy = {0};
    cpy.imageSubresource = (VkImageSubresourceLayers){VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1};
    cpy.imageExtent = (VkExtent3D){W, H, 1};
    vkCmdCopyImageToBuffer(cmd, img, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, buf, 1, &cpy);
    vkEndCommandBuffer(cmd);

    VkSubmitInfo si = {VK_STRUCTURE_TYPE_SUBMIT_INFO};
    si.commandBufferCount = 1; si.pCommandBuffers = &cmd;
    CHECK(vkQueueSubmit(queue, 1, &si, VK_NULL_HANDLE));
    CHECK(vkQueueWaitIdle(queue));

    void *ptr = NULL;
    CHECK(vkMapMemory(dev, bmem, 0, VK_WHOLE_SIZE, 0, &ptr));
    unsigned char *px = ptr;
    int x1 = 16, y1 = 32, x2 = 48;
    unsigned char *a = px + (y1 * W + x1) * 4;
    unsigned char *b = px + (y1 * W + x2) * 4;
    printf("PIXEL left=(%u,%u,%u,%u) right=(%u,%u,%u,%u)\n",
           a[0], a[1], a[2], a[3], b[0], b[1], b[2], b[3]);
    int ok_left = a[0] > 180 && a[1] < 80;
    int ok_right = b[1] > 180 && b[0] < 80;
    printf("RESULT=%s\n", (ok_left && ok_right) ? "PASS" : "FAIL_PIXELS");
    return (ok_left && ok_right) ? 0 : 30;
}
