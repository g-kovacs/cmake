# Artery uses a number of instruments that support generating
# C++ source and header files from plain text templates, like
# protobuf or opp_msgc compilers. Often user wants to generate those
# files before running full build (for static code analysis or linting, for example),
# so we introduce special artery-codegen target, which aggregates all code generating
# tasks and runs them together.

function(artery_mark_as_codegen target)
    # Marks target as codegen task. Use this on targets that
    # generate source files (and maybe compile them) only.

    set(ARTERY_CODEGEN_TARGET artery-codegen)
    if(NOT TARGET ${ARTERY_CODEGEN_TARGET})
        # Codegen target should be always invoked. Custom commands
        # are executed as required - it is a responsibility of the codegen
        # tool provider to ensure sane invocations.
        add_custom_target(${ARTERY_CODEGEN_TARGET} ALL)
    endif()

    add_dependencies(${ARTERY_CODEGEN_TARGET} ${target})
endfunction()

function(generate_opp_message)
    # Generate source files for .msg files (Omnet++ custom messages)
    # via opp_msgc compiler. This function generates sources & headers
    # in PREFIX_DIR for specified MESSAGE, then adds them to provided TARGET.
    # Other arguments may be specified via APPEND_OPTIONS. You may include headers
    # by PREFIX_DIR/header.h file later.

    # Messages are generated under opp_messages/ directory. Additional prefix may be specified
    # by MSG_PREFIX, otherwise prefix is extracted from path to message file. For provided MESSAGE
    # argument equal to some_directory/some_message.msg auto-deduced prefix will be some_directory/,
    # for example.
    # Default root directory may be overridden by DIRECTORY argument.

    # GEN_SOURCES and GEN_INCLUDE_DIR are output variables populated by the generated filenames and
    # the include directory used for generating the messages, respectively.
    # ADDITIONAL_NED_PATHS specifies further NED import paths for message compilation. These paths are
    # passed on to the message compiler as `-I` argumnents.

    set(options_args MSG4)
    set(one_value_args TARGET MESSAGE MSG_PREFIX DIRECTORY GEN_SOURCES GEN_INCLUDE_DIR)
    set(multi_value_args APPEND_OPTIONS ADDITIONAL_NED_PATHS)

    cmake_parse_arguments(args "${options_args}" "${one_value_args}" "${multi_value_args}" ${ARGN})
    if(args_UNPARSED_ARGUMENTS)
        message(SEND_ERROR "generate_opp_message called with invalid arguments: ${args_UNPARSED_ARGUMENTS}")
    endif()

    if(args_DIRECTORY)
        set(output_root ${args_DIRECTORY})
    else()
        set(output_root ${PROJECT_BINARY_DIR}/opp_messages)
    endif()

    if(OMNETPP_VERSION VERSION_GREATER_EQUAL "5.3" AND args_MSG4)
        list(APPEND _args "--msg4")
    elseif(OMNETPP_VERSION VERSION_GREATER_EQUAL "5.3" AND OMNETPP_VERSION VERSION_LESS "6.0" AND NOT args_MSG4)
        list(APPEND _args "--msg6")
    endif()

    cmake_path(GET args_MESSAGE STEM message_name)
    cmake_path(GET args_MESSAGE PARENT_PATH message_directory)
    cmake_path(GET args_MESSAGE FILENAME message_filename)

    if(args_MSG_PREFIX)
        set(message_prefix "${args_MSG_PREFIX}")
    else()
        set(absolute_message_path ${CMAKE_CURRENT_SOURCE_DIR}/${message_directory})
        cmake_path(
            RELATIVE_PATH absolute_message_path
            BASE_DIRECTORY ${PROJECT_SOURCE_DIR}/src
            OUTPUT_VARIABLE message_prefix
        )
    endif()

    set(output_directory "${output_root}/${message_prefix}")
    file(MAKE_DIRECTORY ${output_directory})

    set(message_output_source "${output_directory}/${message_name}_m.cc")
    set(message_output_header "${output_directory}/${message_name}_m.h")

    list(APPEND _args "-s" "_m.cc")

    foreach(include_dir IN LISTS args_ADDITIONAL_NED_PATHS)
        list(APPEND _args "-I" ${include_dir})
    endforeach()

    # Copy the msg file to the output directory (since the -h otion is gone in version 6)
    set(msg_input_process "${output_directory}/${message_filename}")

    add_custom_command(OUTPUT ${msg_input_process}
        COMMAND ${CMAKE_COMMAND} -E copy ${args_MESSAGE} ${msg_input_process}
        COMMENT "Copying ${message_filename} to output directory"
        DEPENDS ${args_MESSAGE}
        WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
        VERBATIM
    )
    list(APPEND _args ${msg_input_process})
    list(APPEND _args ${args_APPEND_OPTIONS})

    add_custom_command(
        OUTPUT "${message_output_source}" "${message_output_header}"
        COMMAND ${OMNETPP_MSGC} ARGS ${_args}
        COMMAND_EXPAND_LISTS
        COMMENT "Generating ${message_prefix}/${message_name}"
        DEPENDS ${msg_input_process} ${OMNETPP_MSGC}
        WORKING_DIRECTORY ${output_directory} VERBATIM
    )

    if(args_TARGET)
        target_sources(${args_TARGET} PRIVATE ${message_output_source} ${message_output_header})
        target_link_libraries(${args_TARGET} PUBLIC OmnetPP::header)
        target_include_directories(${args_TARGET} PUBLIC ${output_root})
    endif()

    if(args_GEN_SOURCES)
        set(${args_GEN_SOURCES} "${message_output_source}" "${message_output_header}" PARENT_SCOPE)
    endif()

    if(args_GEN_INCLUDE_DIR)
        set(${args_GEN_INCLUDE_DIR} ${output_root} PARENT_SCOPE)
    endif()
endfunction()

function(add_opp_message target)
    # Quick way to declare isolated object library, holding
    # just message header and source file. This function also
    # includes created target in codegen.

    # this wrapper supports all args for generate_opp_message, except for TARGET,
    # which you provide via first non-named argument to this function.

    add_library(${target} OBJECT)
    generate_opp_message(TARGET ${target} ${ARGN})
    artery_mark_as_codegen(${target})
endfunction()

function(add_protobuf target)
    # Same as add_opp_message, but for protobuf messages. This
    # wrapper uses older protobuf_generate_cpp, so only proto files
    # are expected with PROTOS parameter.

    set(one_value_args PROTOS)
    cmake_parse_arguments(args "" "${one_value_args}" "" ${ARGN})

    if(args_UNPARSED_ARGUMENTS)
        message(SEND_ERROR "add_protobuf called with invalid arguments: ${args_UNPARSED_ARGUMENTS}")
    endif()

    protobuf_generate_cpp(proto_sources proto_headers ${args_PROTOS})
    add_library(${target} OBJECT ${proto_sources} ${proto_headers})
    artery_mark_as_codegen(${target})

    target_link_libraries(${target} PUBLIC protobuf::libprotobuf)
    target_include_directories(${target} PUBLIC ${CMAKE_CURRENT_BINARY_DIR})
endfunction()
