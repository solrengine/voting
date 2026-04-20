module ApplicationHelper
  def nav_link_to(label, path)
    base = "transition-colors text-sm"
    classes = if current_page?(path)
      "#{base} text-gray-900 dark:text-white font-semibold"
    else
      "#{base} text-gray-600 hover:text-gray-900 dark:text-gray-300 dark:hover:text-white"
    end
    link_to(label, path, class: classes)
  end
end
