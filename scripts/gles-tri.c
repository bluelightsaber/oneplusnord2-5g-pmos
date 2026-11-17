/* gles-tri.c: draw one triangle into a 64x64 FBO with EGL surfaceless + GLES2, read back the centre pixel.
 * Tells whether the GPU executes vertex/fragment jobs at all. Build: cc -o gles-tri gles-tri.c -lEGL -lGLESv2 */
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <stdio.h>
#include <string.h>
int main(void) {
	PFNEGLGETPLATFORMDISPLAYEXTPROC gpd = (void *)eglGetProcAddress("eglGetPlatformDisplayEXT");
	EGLDisplay d = gpd(EGL_PLATFORM_SURFACELESS_MESA, EGL_DEFAULT_DISPLAY, NULL);
	if (!eglInitialize(d, NULL, NULL)) { puts("eglInitialize failed"); return 1; }
	EGLint ca[] = { EGL_SURFACE_TYPE, EGL_PBUFFER_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT, EGL_NONE }, nc; EGLConfig c;
	eglChooseConfig(d, ca, &c, 1, &nc); eglBindAPI(EGL_OPENGL_ES_API);
	EGLint xa[] = { EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE };
	EGLContext x = eglCreateContext(d, nc ? c : NULL, EGL_NO_CONTEXT, xa);
	if (!eglMakeCurrent(d, EGL_NO_SURFACE, EGL_NO_SURFACE, x)) { puts("makecurrent failed"); return 1; }
	printf("renderer: %s\n", glGetString(GL_RENDERER));
	GLuint fb, rb; glGenFramebuffers(1, &fb); glBindFramebuffer(GL_FRAMEBUFFER, fb);
	glGenRenderbuffers(1, &rb); glBindRenderbuffer(GL_RENDERBUFFER, rb); glRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA4, 64, 64);
	glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, rb);
	const char *vs = "attribute vec2 p; void main(){ gl_Position = vec4(p, 0.0, 1.0); }";
	const char *fs = "precision mediump float; void main(){ gl_FragColor = vec4(1.0, 0.5, 0.0, 1.0); }";
	GLuint v = glCreateShader(GL_VERTEX_SHADER), f = glCreateShader(GL_FRAGMENT_SHADER), pr = glCreateProgram();
	glShaderSource(v, 1, &vs, NULL); glCompileShader(v); glShaderSource(f, 1, &fs, NULL); glCompileShader(f);
	glAttachShader(pr, v); glAttachShader(pr, f); glBindAttribLocation(pr, 0, "p"); glLinkProgram(pr); glUseProgram(pr);
	float t[] = { -1, -1, 3, -1, -1, 3 };
	glViewport(0, 0, 64, 64); glClearColor(0, 0, 1, 1); glClear(GL_COLOR_BUFFER_BIT);
	glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, t); glEnableVertexAttribArray(0); glDrawArrays(GL_TRIANGLES, 0, 3);
	unsigned char px[4] = { 0 }; glReadPixels(32, 32, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, px);
	printf("pixel: %u %u %u %u (expect ~255 128 0 255; 0 0 255 255 = clear only)\n", px[0], px[1], px[2], px[3]);
	printf("glError 0x%x\n", glGetError());
	return 0;
}
