require 'xcodeproj'
project = Xcodeproj::Project.open('Brainstorm+.xcodeproj')
target = project.targets.first

def ensure_group(project, path)
  parts = path.split('/')
  group = project.main_group
  parts.each do |part|
    group = group.children.find { |c| c.name == part || c.path == part } || group.new_group(part)
  end
  group
end

group = ensure_group(project, 'Brainstorm+/Shared/DesignSystem/Modifiers')
ref = group.new_file('SquishyButtonStyle.swift')
target.add_file_references([ref])
project.save
