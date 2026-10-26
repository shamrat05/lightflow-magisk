#include <cerrno>
#include <cstdio>
#include <cstring>
#include <fcntl.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <unistd.h>

static bool same_file(const struct stat& a, const struct stat& b) {
    return a.st_dev == b.st_dev && a.st_ino == b.st_ino;
}

static int fail(const char* operation) {
    std::fprintf(stderr, "hosts-bind: %s: %s\n", operation, std::strerror(errno));
    return 1;
}

int main(int argc, char** argv) {
    if (argc != 3 || argv[1][0] != '/' || argv[2][0] != '/') {
        std::fprintf(stderr, "Usage: hosts-bind /absolute/source /absolute/target\n");
        return 2;
    }
    struct stat source {}, target {};
    const int fd = open(argv[1], O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
    if (fd < 0) return fail("open source");
    if (fstat(fd, &source) || lstat(argv[2], &target)) {
        const int saved = errno;
        close(fd);
        errno = saved;
        return fail("stat");
    }
    if (!S_ISREG(source.st_mode) || !S_ISREG(target.st_mode)
            || !source.st_nlink || !target.st_nlink) {
        close(fd);
        errno = EINVAL;
        return fail("regular linked files required");
    }
    char pinned_source[64];
    std::snprintf(pinned_source, sizeof(pinned_source), "/proc/self/fd/%d", fd);
    if (mount(pinned_source, argv[2], nullptr, MS_BIND, nullptr)) {
        const int saved = errno;
        close(fd);
        errno = saved;
        return fail("bind");
    }
    int saved = 0;
    if (mount(nullptr, argv[2], nullptr, MS_REMOUNT | MS_BIND | MS_RDONLY, nullptr)) {
        saved = errno;
    } else {
        struct stat actual {};
        struct statvfs filesystem {};
        if (stat(argv[2], &actual) || statvfs(argv[2], &filesystem)) saved = errno;
        else if (!same_file(source, actual) || !(filesystem.f_flag & ST_RDONLY)) saved = EIO;
    }
    if (!saved) {
        const int writable = open(argv[2], O_WRONLY | O_NOFOLLOW | O_CLOEXEC);
        if (writable >= 0) {
            close(writable);
            saved = EIO;
        } else if (errno != EROFS) saved = errno;
    }
    if (saved) {
        // A concurrent replacement belongs to its owner. Remove only our inode.
        struct stat actual {};
        if (!stat(argv[2], &actual) && same_file(source, actual)) {
            if (umount2(argv[2], MNT_DETACH)) fail("rollback");
        }
        close(fd);
        errno = saved;
        return fail("read-only verification");
    }
    close(fd);
    std::puts("hosts-bind: read-only bind verified");
    return 0;
}
