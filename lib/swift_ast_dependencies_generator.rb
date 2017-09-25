require 'objc_dependency_tree_generator_helper'
require 'parser/swift_ast_parser'

class SwiftAstDependenciesGenerator

  def initialize(ast_file)
    @ast_file = ast_file
  end

  # @return [DependencyTree]
  def generate_dependencies

    @tree = DependencyTree.new
    @context = []
    @generics_context = []

    @ast_tree = SwiftAST::Parser.new().parse(File.read(@ast_file))
    # @ast_tree.dump
    scan_source_files

    @tree
  end

  def scan_source_files
    classes = @ast_tree.find_nodes("class_decl")
    classes.each { |node| 
      classname = node.parameters.first
      return unless classname
      @tree.register(classname, DependencyItemType::CLASS) 
    }

    protocols = @ast_tree.find_nodes("protocol")
    protocols.each { |node| 
      protoname = node.parameters.first
      return unless protoname
      @tree.register(protoname, DependencyItemType::PROTOCOL) 
    }

    classes.each { |node| 
      classname = node.parameters.first
      return unless classname
      generic_names = register_generic_parameters(node, classname) 
      @generics_context << generic_names

      register_inheritance(node, classname) 
      register_variables(node, classname) 
      register_calls(node, classname) 
      register_function_parameters(node, classname) 

      @generics_context.pop

    }

    protocols.each { |node|
      proto_name = node.parameters.first
      register_inheritance(node, proto_name) if proto_name
    }

  end

  def register_inheritance(node, name)
    inheritance = node.parameters.drop_while { |el| el != "inherits:" }
    inheritance = inheritance.drop(1)
    inheritance.each { |inh| 
      inh_name = inh.chomp(",")
      add_tree_dependency(name, inh_name, DependencyLinkType::INHERITANCE)
    }
  end

  def register_generic_parameters(node, name)
    generic = node.parameters[1] # Second parameter
    return [] unless generic
    return [] unless generic[0] + generic[-1] == "<>" 

    # REmove brackets
    generic = generic[1..-2]

    generic_decls = []
    generic.split(",").each { |decl|
      parts = decl.split(":")
      leftPart = parts[0]
      rightPart = parts[1]
      return unless rightPart && leftPart

      generic_name = leftPart.strip || leftPart
      generic_decls << generic_name

      rightPart.split("&").each { |protocol_or_class|
        proto_name = protocol_or_class.strip || protocol_or_class
        add_tree_dependency(name, proto_name, DependencyLinkType::INHERITANCE)
      }
    }

    generic_decls
  end


  def register_variables(node, name)  
    node.find_nodes("var_decl").each { |variable|
      type_decl = variable.parameters.find { |el| el.start_with?("type=") }
      return unless type_decl
      type_name = type_decl.sub("type=", '')[1..-2].chomp("?")
      add_tree_dependency(name, type_name, DependencyLinkType::IVAR)
    }
  end  

  def register_calls(node, name)
    node.find_nodes("call_expr").each { |variable|
      type_decl = variable.parameters.find { |el| el.start_with?("type=") }
      return unless type_decl
      type_name = type_decl.sub("type=", '')[1..-2].chomp("?")
      add_tree_dependency(name, type_name, DependencyLinkType::CALL)
    }
  end

  def register_function_parameters(node, name)  
    node.find_nodes("func_decl").each { |func_decl|

      func_decl.find_nodes("parameter_list").each { |param_list|
        param_list.find_nodes("parameter").each { |parameter|
          type_decl = parameter.parameters.find { |el| el.start_with?("type=") }
          return unless type_decl
          type_name = type_decl.sub("type=", '')[1..-2].chomp("?")
          add_tree_dependency(name, type_name, DependencyLinkType::PARAMETER)
        }
      }

      func_decl.find_nodes("result").each { |result_decl|
        result_decl.find_nodes("type_ident").each { |type_id|
          type_id.find_nodes("component").each { |comp|
            type_decl = comp.parameters.find { |el| el.start_with?("id=") }
            return unless type_decl
            type_name = type_decl.sub("id=", '')[1..-2].chomp("?")
            add_tree_dependency(name, type_name, DependencyLinkType::PARAMETER)
          }
        }
      }
    }
  end 

  def normalized_name(the_name)
    the_name[/(\w|\d)+/]
  end

  def add_tree_dependency(from_name, to_name, type) 
    # skip names from generics
    # we also will need to skip generics_from_functions
    skip_names = @generics_context.last || []

    from = normalized_name(from_name)
    return if skip_names.include? from

    to = normalized_name(to_name)
    return if skip_names.include? to

    @tree.add(from, to, type)
  end




end
