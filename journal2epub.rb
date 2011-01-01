###############################################################################
#                                                                             #
#         #                       #  ###             #           #            #
#            ### # # ### ##   ##  #    # ### ### # # ###     ### ###          #
#         #  # # # # #   # # # #  #  ### ##  # # # # # #     #   # #          #
#         #  ### ### #   # # ###  ## #   ### ### ### ###     #   ###          #
#        #                           ###     #            #                   #
#                                                                             #
#        journal2epub.rb (c) 2011 Louis St-Amour, MIT Licensed (Expat)        #
# Command-line tool to convert an issue of code4lib journal into epub format. #
#                                                                             #
# Installation (ideally with rvm): gem install bundler && bundle install      #
# Usage: ruby journal2epub.rb issue-number                                    #
#                                                                             #
#                                   e.g. ruby journal2epub.rb 12 will convert #
#                     http://journal.code4lib.org/issues/issue12 into 12.epub #
###############################################################################

require 'rubygems'
require 'bundler/setup'

require 'nokogiri'