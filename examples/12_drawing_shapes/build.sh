set +x
rsync -av --delete-during $(realpath $PWD/../..) ~/tmp/kivysv
export P4A_kivent_core_DIR=~/tmp/kivysv/kivent
#export P4A_kivy_DIR=$PWD/kivy

buildozer --verbose android debug

