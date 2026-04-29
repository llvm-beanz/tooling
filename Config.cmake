set(LLVM_ENABLE_ASSERTIONS On CACHE BOOL "")
set(LLVM_TARGETS_TO_BUILD Native CACHE STRING "")
set(LLVM_EXPERIMENTAL_TARGETS_TO_BUILD "DirectX;SPIRV" CACHE STRING "")
set(CMAKE_BUILD_TYPE RelWithDebInfo CACHE STRING "")
set(CMAKE_INSTALL_PREFIX $ENV{PWD}/install CACHE STRING "")
set(CLANG_APPEND_VC_REV On CACHE BOOL "")
set(LLVM_BUILD_LLVM_DYLIB On CACHE BOOL "")
set(CLANG_ENABLE_HLSL On CACHE BOOL "")

set(LLVM_INCLUDE_DXIL_TESTS On CACHE BOOL "")
set(DXIL_DIS /usr/local/bin/dxil-dis CACHE STRING "")
set(CLANG_ENABLE_HLSL On CACHE BOOL "")

set(LLVM_ENABLE_PROJECTS clang
                         clang-tools-extra
                         mlir CACHE STRING "")

if (EXISTS $ENV{HOME}/dev/offload-test-suite/)
  set(LLVM_EXTERNAL_OFFLOADTEST_SOURCE_DIR $ENV{HOME}/dev/offload-test-suite/ CACHE STRING "")
  set(LLVM_EXTERNAL_PROJECTS OffloadTest CACHE STRING "")
endif()

set(LLVM_EXTERNAL_PROJECTS ${_external_projects} CACHE STRING "")

if (EXISTS $ENV{HOME}/dev/offload-golden-images/)
  set(GOLDENIMAGE_DIR $ENV{HOME}/dev/offload-golden-images/ CACHE STRING "")
endif()


if (EXISTS $ENV{HOME}/dev/DirectXShaderCompiler/build-rel/bin/)
  set(DXC_DIR $ENV{HOME}/dev/DirectXShaderCompiler/build-rel/bin/ CACHE STRING "")
endif()


# setup toolchain
set(LLVM_INSTALL_TOOLCHAIN_ONLY ON CACHE BOOL "")
set(LLVM_TOOLCHAIN_TOOLS
  dsymutil
  llvm-cov
  llvm-dwarfdump
  llvm-profdata
  llvm-objdump
  llvm-nm
  llvm-size
  CACHE STRING "")

string(TOUPPER "${CMAKE_BUILD_TYPE}" uppercase_CMAKE_BUILD_TYPE)

find_program(SCCACHE sccache HINTS /usr/local/bin)
if (SCCACHE)
  set(CMAKE_C_COMPILER_LAUNCHER ${SCCACHE} CACHE STRING "")
  set(CMAKE_CXX_COMPILER_LAUNCHER ${SCCACHE} CACHE STRING "")
endif()

if(uppercase_CMAKE_BUILD_TYPE STREQUAL "DEBUG")
  set(LLVM_OPTIMIZED_TABLEGEN On CACHE BOOL "")
  set(LLVM_USE_SANITIZER "Address;Undefined" CACHE STRING "")
  set(LLVM_OPTIMIZE_SANITIZED_BUILDS Off CACHE BOOL "")
endif()
if (CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG} -fsanitize=address,undefined -fno-sanitize=vptr,function -fno-sanitize-recover=all")
  set(CMAKE_C_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG} -fsanitize=address,undefined -fno-sanitize=vptr,function -fno-sanitize-recover=all")
  set(LLVM_OPTIMIZED_TABLEGEN On CACHE BOOL "")
endif()

find_program(CLANG_TIDY clang-tidy)
if (CLANG_TIDY)
  set(OFFLOADTEST_USE_CLANG_TIDY On CACHE BOOL "")
  set(OFFLOADTEST_CLANG_TIDY_APPLY_FIX On CACHE BOOL "")
endif()

if(APPLE AND NOT $ENV{TOOLCHAINS} STREQUAL "")
  message("Querying for compilers from $ENV{TOOLCHAINS}...")
  execute_process(COMMAND xcrun -toolchain $ENV{TOOLCHAINS} -find clang
   OUTPUT_VARIABLE CMAKE_C_COMPILER
   ERROR_QUIET
   OUTPUT_STRIP_TRAILING_WHITESPACE)

  execute_process(COMMAND xcrun -toolchain $ENV{TOOLCHAINS} -find clang++
   OUTPUT_VARIABLE CMAKE_CXX_COMPILER
   ERROR_QUIET
   OUTPUT_STRIP_TRAILING_WHITESPACE)

  set(CMAKE_C_COMPILER ${CMAKE_C_COMPILER} CACHE STRING "")
  set(CMAKE_ASM_COMPILER ${CMAKE_C_COMPILER} CACHE STRING "")
  set(CMAKE_CXX_COMPILER ${CMAKE_CXX_COMPILER} CACHE STRING "")
endif()
