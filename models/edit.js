function editUser($li, editUserAttrs) {
  $.ajax(
  {
    type: 'PUT',
    url :  `http://localhost:3000/users/${$li.attr('id')}`,
    data: editUserAttrs
  }).then(function(user){
    console.log("Update confirmed");
    $li.find('name').html(user.name);
    $li.find('photo').html(user.photo);
  }, function(err) {
    console.log(err)
  });
}
